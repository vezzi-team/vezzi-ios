import Combine
import Foundation

@MainActor
final class ShoppingListViewModel: ObservableObject {
    enum ContentState { case products, loading, empty, offline, unavailable }
    @Published var mode = ShoppingListMode.cheaper
    @Published private(set) var selectedProduct: Product?
    @Published private(set) var selectedProductOffer: ProductOffer?
    @Published private(set) var relatedProducts: [Product] = []
    @Published var routePlan: ShoppingPlan?
    @Published private var catalogItems: [String: CatalogItem] = [:]
    let list: ShoppingListRepository
    private let catalog: any CatalogRepository
    private var subscriptions = Set<AnyCancellable>()
    private var relatedSubscription: AnyCancellable?

    init(catalog: any CatalogRepository, list: ShoppingListRepository) {
        self.catalog = catalog
        self.list = list
        list.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        list.selection.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        list.$account.removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.routePlan = nil
            self?.dismissProduct()
            self?.selectedProductOffer = nil
        }.store(in: &subscriptions)
        catalog.observeAllProducts().sink { [weak self] items in
            self?.catalogItems = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    var contentState: ContentState {
        guard list.selection.quantities.isEmpty else { return .products }
        // A confirmed absence of a cart is usable data too, including after an offline restart.
        guard list.accountID != nil, !list.hasResolvedCart else { return .empty }
        if list.isBusy { return .loading }
        if list.failure == .offline { return .offline }
        if list.failure != nil { return .unavailable }
        return .empty
    }

    var products: [Product] {
        let fallback = Dictionary(uniqueKeysWithValues: (list.cart?.items ?? []).map { ($0.product.id, $0.product) })
        let assigned = plannedOffers
        return list.selection.quantities.keys.sorted().map { id in
            var product = catalogItems[id].map { Product(catalog: $0) } ?? fallback[id].map {
                Product(id: $0.id, name: $0.name, brand: $0.brand ?? "", packageQuantity: $0.packageQuantity,
                        packageUnit: $0.packageUnit, category: $0.category.map(ProductCategory.init(rawValue:)), offers: [])
            } ?? Product(id: id, name: Texts.ShoppingList.unavailableProduct, brand: "", packageQuantity: nil,
                         packageUnit: nil, category: nil, offers: [])
            if let offer = assigned[id] {
                product.offers = [offer]
            }
            return product
        }
    }

    private var plannedOffers: [String: ProductOffer] {
        Dictionary((plan?.stops ?? []).flatMap { stop in
            stop.items.map { item in
                (item.product.id, ProductOffer(id: "plan.\(stop.store.id).\(item.product.id)",
                                               storeID: stop.store.id, name: stop.store.name, price: item.unitPrice,
                                               cardPrice: item.cardPrice, priceConditions: item.priceConditions,
                                               address: stop.store.address, chainName: stop.store.chainName))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    var cheapest: ShoppingPlan? {
        list.planResult?.plans.min {
            if $0.total != $1.total { return $0.total < $1.total }
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds < $1.totalSeconds }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var fastest: ShoppingPlan? {
        list.planResult?.plans.min {
            if $0.totalSeconds != $1.totalSeconds { return $0.totalSeconds < $1.totalSeconds }
            if $0.total != $1.total { return $0.total < $1.total }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var plan: ShoppingPlan? { mode == .cheaper ? cheapest : fastest }
    var comparisonPrice: Decimal? { mode == .cheaper ? fastest?.total : cheapest?.total }

    var priceSavings: Decimal? {
        guard let cheapest, let fastest else { return nil }
        return max(.zero, fastest.total - cheapest.total)
    }

    var savedMinutes: Int { max(0, ((cheapest?.totalSeconds ?? 0) - (fastest?.totalSeconds ?? 0)) / 60) }
    var needsAuthentication: Bool { list.accountID == nil || list.failure == .authenticationRequired }

    var message: String? {
        let messages = [list.isBusy ? nil : synchronizationMessage,
                        list.isPlanCached && plan != nil ? Texts.ShoppingList.cachedCalculation : nil,
                        list.hasCacheFailure ? Texts.ShoppingList.cacheError : nil].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var synchronizationMessage: String? {
        if needsAuthentication {
            // The unavailable state already offers sign-in; an untouched guest list needs no warning.
            return contentState == .products || (contentState == .empty && list.failure == .authenticationRequired)
                ? Texts.ShoppingList.signInDescription : nil
        }
        if let failure = list.failure {
            switch failure {
            case .authenticationRequired: return Texts.ShoppingList.signInDescription
            case .offline: return nil
            case .limit: return Texts.ShoppingList.limitDescription
            case .cartUnavailable: return Texts.ShoppingList.cartUnavailable
            case .otherCartSyncFailed: return Texts.ShoppingList.otherCartSyncFailed
            case .unavailable: return contentState == .unavailable ? nil : Texts.ShoppingList.loadError
            }
        }
        guard let result = list.planResult, result.plans.isEmpty else { return nil }
        switch result.problem {
        case "items_unavailable": return Texts.ShoppingList.itemsUnavailable
        case "store_limit_too_low": return Texts.ShoppingList.storeLimit
        case "time_limit_too_low": return Texts.ShoppingList.timeLimit
        case "radius_too_small": return Texts.ShoppingList.radiusLimit
        case "route_unavailable": return Texts.ShoppingList.routeUnavailable
        default: return Texts.ShoppingList.noPlans
        }
    }

    func refresh() async {
        async let refreshList: Void = list.refresh()
        if catalog.canRefresh { try? await catalog.refresh() }
        await refreshList
    }

    func showProduct(_ product: Product) {
        relatedSubscription?.cancel()
        relatedProducts = []
        selectedProductOffer = plannedOffers[product.id]
        selectedProduct = catalogItems[product.id].map { Product(catalog: $0) } ?? product
        relatedSubscription = catalog.observeRelatedProducts(to: product.id, storeID: nil)
            .prefix(1).sink { [weak self] in self?.relatedProducts = $0.map { Product(catalog: $0) } }
    }

    func dismissProduct() {
        relatedSubscription?.cancel()
        relatedSubscription = nil
        // Keep the offer and alternatives stable while the sheet is dismissing.
        selectedProduct = nil
    }
}

enum ShoppingListMode: String, CaseIterable, Identifiable {
    case cheaper
    case faster
    var id: Self { self }
}
