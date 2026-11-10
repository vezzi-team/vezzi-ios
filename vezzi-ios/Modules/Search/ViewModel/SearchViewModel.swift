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
    @Published private(set) var isCacheUnavailable = false
    @Published private(set) var catalogStatus = CatalogStatus()

    var canRefresh: Bool { repository.canRefresh }
    var isResultLimitReached: Bool { items.count == CatalogSearch.resultLimit }
    var isRefreshing: Bool { catalogStatus.isRefreshing }
    var refreshErrorMessage: String? { catalogStatus.failure.map { _ in Texts.Search.refreshError } }

    private let stores: [String: SearchStoreInfo]
    private let groupRanks: [String: Int]
    private var products: [Product] = []
    private let repository: any CatalogRepository
    private var querySubscription: AnyCancellable?
    private var resultsSubscription: AnyCancellable?
    private var cacheSubscription: AnyCancellable?
    private var relatedSubscription: AnyCancellable?
    private var statusSubscription: AnyCancellable?

    init(repository: any CatalogRepository, stores: [String: SearchStoreInfo] = [:], groupOrder: [String] = []) {
        self.repository = repository
        self.stores = stores
        groupRanks = Dictionary(groupOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        cacheSubscription = repository.cacheState.sink { [weak self] state in
            self?.isCacheUnavailable = state == .unavailable
        }
        statusSubscription = repository.status.sink { [weak self] status in
            self?.catalogStatus = status
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
        guard canRefresh else { return }
        // Shared status and single-flight requests belong to the repository.
        try? await repository.refresh()
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
                          address: nil, storeID: nil, walkingMinutes: nil,
                          products: items.compactMap { productsByID[$0.id] }.sorted(by: priceOrder))
        }.sorted {
            let lhsRank = groupRanks[$0.id, default: Int.max]
            let rhsRank = groupRanks[$1.id, default: Int.max]
            return lhsRank == rhsRank ? $0.id < $1.id : lhsRank < rhsRank
        }
    }

    private func fasterSections() -> [SearchSection] {
        var byStore: [String: [Product]] = [:]
        for product in products {
            for offer in product.offers where offer.inStock != false {
                var scoped = product
                scoped.offers = [offer]
                byStore[offer.storeID, default: []].append(scoped)
            }
        }
        return byStore.map { id, products in
            let offer = products.first?.offers.first
            return SearchSection(id: id, title: offer?.storeTitle ?? "", address: offer?.address, storeID: id,
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
        Product(catalog: item, distances: stores.mapValues(\.distance))
    }

    private enum Const {
        static let searchDelay = 250
    }
}
