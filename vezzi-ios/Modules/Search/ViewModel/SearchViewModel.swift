import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var mode: ProductSearchMode = .cheaper {
        didSet { if mode != oldValue { rebuildSections() } }
    }
    @Published private(set) var sections: [SearchSection] = []
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var selectedProduct: Product?
    @Published private(set) var selectedProductStoreID: String?
    @Published private(set) var relatedProducts: [Product] = []
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCacheUnavailable = false

    var canRefresh: Bool { repository.canRefresh }
    var isResultLimitReached: Bool { items.count == CatalogSearch.resultLimit }

    private let stores: [String: SearchStoreInfo]
    private let groupRanks: [String: Int]
    private var products: [Product] = []
    private let repository: any CatalogRepository
    private var querySubscription: AnyCancellable?
    private var resultsSubscription: AnyCancellable?
    private var cacheSubscription: AnyCancellable?
    private var relatedSubscription: AnyCancellable?

    init(repository: any CatalogRepository, stores: [String: SearchStoreInfo] = [:], groupOrder: [String] = []) {
        self.repository = repository
        self.stores = stores
        groupRanks = Dictionary(groupOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        cacheSubscription = repository.cacheState.sink { [weak self] state in
            self?.isCacheUnavailable = state == .unavailable
        }
        observe(query: "")
        querySubscription = $query
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(Const.searchDelay), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.observe(query: $0) }
    }

    nonisolated deinit {}

    func retry() async {
        async let cacheRetry: Void = repository.prepareCache()
        await refresh()
        await cacheRetry
    }

    func refresh() async {
        guard canRefresh, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await repository.refresh()
            refreshErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            // Existing results remain available when the source cannot be reached.
            refreshErrorMessage = Texts.Search.refreshError
        }
    }

    private func observe(query: String) {
        resultsSubscription?.cancel()
        resultsSubscription = repository.observeProducts(matching: query)
            .sink { [weak self] items in
                guard let self else { return }
                self.items = items
                self.products = items.map(self.product)
                self.rebuildSections()
            }
    }

    // MARK: - Presentation

    func showProduct(_ product: Product, storeID: String? = nil) {
        relatedSubscription?.cancel()
        relatedProducts = []
        selectedProductStoreID = storeID
        selectedProduct = product
        relatedSubscription = repository.observeRelatedProducts(to: product.id, storeID: storeID)
            // Keep one detail snapshot so later catalog updates cannot invalidate pushed pages.
            .prefix(1)
            .sink { [weak self] items in
                guard let self else { return }
                self.relatedProducts = items.map(self.product).compactMap { product in
                    guard let storeID else { return product }
                    guard let offer = product.offers.first(where: { $0.storeID == storeID && $0.inStock != false }) else { return nil }
                    var scoped = product
                    scoped.offers = [offer]
                    return scoped
                }.sorted(by: self.priceOrder)
            }
    }

    func dismissProduct() {
        relatedSubscription?.cancel()
        relatedSubscription = nil
        selectedProduct = nil
        // Retain the snapshot during dismissal; the next selection replaces it.
    }

    private func rebuildSections() {
        switch mode {
        case .cheaper: sections = cheaperSections()
        case .faster: sections = fasterSections()
        }
    }

    private func cheaperSections() -> [SearchSection] {
        let productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        return Dictionary(grouping: items, by: { $0.product.groupID }).map { id, items in
            SearchSection(id: id, title: items.first?.product.category ?? items.first?.product.name ?? "",
                          storeID: nil, walkingMinutes: nil,
                          products: items.compactMap { productsByID[$0.id] }.sorted(by: priceOrder))
        }.sorted {
            let lhsRank = groupRanks[$0.id, default: Int.max]
            let rhsRank = groupRanks[$1.id, default: Int.max]
            return lhsRank == rhsRank ? $0.id < $1.id : lhsRank < rhsRank
        }
    }

    private func fasterSections() -> [SearchSection] {
        var byStore: [String: [Product]] = [:]
        var names: [String: String] = [:]
        for product in products {
            for offer in product.offers where offer.inStock != false {
                var scoped = product
                scoped.offers = [offer]
                byStore[offer.storeID, default: []].append(scoped)
                names[offer.storeID] = offer.name
            }
        }
        return byStore.map { id, products in
            SearchSection(id: id, title: names[id] ?? "", storeID: id,
                          walkingMinutes: stores[id]?.walkingMinutes,
                          products: products.sorted(by: priceOrder))
        }.sorted {
            let lhsTime = $0.walkingMinutes ?? Int.max
            let rhsTime = $1.walkingMinutes ?? Int.max
            return lhsTime == rhsTime ? $0.id < $1.id : lhsTime < rhsTime
        }
    }

    private func priceOrder(_ lhs: Product, _ rhs: Product) -> Bool {
        switch (lhs.lowestPrice, rhs.lowestPrice) {
        case let (left?, right?) where left != right: return left < right
        case (nil, _?): return false
        case (_?, nil): return true
        default: return lhs.id < rhs.id
        }
    }

    private func product(_ item: CatalogItem) -> Product {
        let offers = Dictionary(grouping: item.offers, by: { $0.store.id }).values
            .compactMap { $0.min(by: preferredOffer) }
            .sorted { $0.store.name == $1.store.name ? $0.store.id < $1.store.id : $0.store.name < $1.store.name }
        return Product(id: item.id, name: item.product.name, brand: item.product.brand ?? "",
                       packageQuantity: item.product.packageQuantity, packageUnit: item.product.packageUnit,
                       category: nil, offers: offers.map { cached in
                           ProductOffer(id: cached.id, storeID: cached.store.id, name: cached.store.name,
                                        price: cached.offer.price, currency: cached.offer.currency,
                                        inStock: cached.offer.inStock, distance: stores[cached.store.id]?.distance)
                       })
    }

    private func preferredOffer(_ lhs: CachedOffer, _ rhs: CachedOffer) -> Bool {
        // Prefer purchasable offers, then the lowest price. IDs break ties deterministically.
        let lhsAvailable = lhs.offer.inStock != false
        let rhsAvailable = rhs.offer.inStock != false
        if lhsAvailable != rhsAvailable { return lhsAvailable }
        return lhs.offer.price == rhs.offer.price ? lhs.id < rhs.id : lhs.offer.price < rhs.offer.price
    }

    private enum Const {
        static let searchDelay = 250
    }
}
