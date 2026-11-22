import Combine
import Foundation

@MainActor
final class ShoppingListViewModel: ObservableObject {
    enum ContentState { case products, loading, empty, offline, unavailable }
    @Published var mode = ShoppingMode.cheaper
    @Published private(set) var selectedProduct: Product?
    @Published private(set) var selectedProductOffer: ProductOffer?
    @Published private(set) var relatedProducts: [Product] = []
    @Published var routes: ShoppingRoutesSnapshot?
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
            self?.routes = nil
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
                (item.product.id, item.assignedOffer(in: stop.store))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    var cheapest: ShoppingPlan? { list.planResult?.plans.first }
    var fastest: ShoppingPlan? { list.planResult?.fastestPlans?.first }

    var plan: ShoppingPlan? { list.trip?.plan ?? (mode == .cheaper ? cheapest : fastest) }
    var comparisonPrice: Decimal? { mode == .cheaper ? fastest?.total : cheapest?.total }

    var priceSavings: Decimal? {
        guard let cheapest, let fastest else { return nil }
        return max(.zero, fastest.total - cheapest.total)
    }

    var savedMinutes: Int {
        guard let cheapest, let fastest else { return 0 }
        return max(0, (cheapest.totalSeconds - fastest.totalSeconds) / 60)
    }
    var needsAuthentication: Bool { list.accountID == nil || list.failure == .authenticationRequired }

    var message: String? {
        let messages = [list.isBusy ? nil : synchronizationMessage,
                        Texts.ShoppingList.planningProblem(for: list.planResult),
                        cachedCalculationMessage,
                        list.hasCacheFailure ? Texts.ShoppingList.cacheError : nil].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private var cachedCalculationMessage: String? {
        guard list.isPlanCached, let result = list.planResult else { return nil }
        if mode == .faster, result.fastestPlans == nil, !result.plans.isEmpty {
            return Texts.ShoppingList.refreshForFastestRoutes
        }
        return Texts.ShoppingList.cachedCalculation
    }

    private var synchronizationMessage: String? {
        if needsAuthentication {
            // The unavailable state already offers sign-in; an untouched guest list needs no warning.
            return contentState == .products || (contentState == .empty && list.failure == .authenticationRequired)
                ? Texts.ShoppingList.signInDescription : nil
        }
        switch list.failure {
        case .none, .offline: return nil
        case .authenticationRequired: return Texts.ShoppingList.signInDescription
        case .limit: return Texts.ShoppingList.limitDescription
        case .cartUnavailable: return Texts.ShoppingList.cartUnavailable
        case .otherCartSyncFailed: return Texts.ShoppingList.otherCartSyncFailed
        case .unavailable: return contentState == .unavailable ? nil : Texts.ShoppingList.loadError
        }
    }

    func refresh() async {
        async let refreshList: Void = list.refresh()
        if catalog.canRefresh { try? await catalog.refresh() }
        await refreshList
    }

    func showRoutes(startsAtSummary: Bool = false) {
        if let trip = list.trip {
            routes = ShoppingRoutesSnapshot(plans: [trip.plan], mode: mode, origin: trip.origin, isSaved: false,
                                           routeOptions: .init(returnToStart: trip.returnsHome),
                                           originAddress: trip.originAddress, startsAtSummary: startsAtSummary)
            return
        }
        guard !startsAtSummary, let result = list.planResult else { return }
        routes = ShoppingRoutesSnapshot(plans: mode.plans(in: result), mode: mode, origin: list.origin, isSaved: list.isPlanCached,
                                        routeOptions: list.routeOptions, originAddress: list.originAddress)
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
