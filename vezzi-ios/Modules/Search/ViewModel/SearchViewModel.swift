import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            if normalizedQuery != oldValue.trimmingCharacters(in: .whitespacesAndNewlines) {
                startSearch(debounce: true)
            }
        }
    }
    @Published var mode: ShoppingMode = .cheaper {
        didSet { if mode != oldValue { rebuildSections() } }
    }
    @Published private(set) var sections: [SearchSection] = []
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var selectedProduct: Product?
    @Published private(set) var selectedProductStoreID: String?
    @Published private(set) var emptyState = CatalogEmptyState.empty

    var canRefresh: Bool { repository.canRefresh }
    var resultsMatchQuery: Bool { displayedQuery == normalizedQuery }
    var showsSections: Bool { !sections.isEmpty && !isLoadingReplacement }
    // Keep the picker reachable when Fastest has no offers but Best price still has products.
    var showsModePicker: Bool { !items.isEmpty && !isLoadingReplacement }

    private let stores: [String: SearchStoreInfo]
    private let groupRanks: [String: Int]
    private var products: [Product] = []
    private let repository: any CatalogRepository
    private var searchTask: Task<Void, Never>?
    private var connectivitySubscription: AnyCancellable?
    private var catalogEmptyState = CatalogEmptyState.empty
    private var queryFeedback: CatalogEmptyState?
    private var displayedQuery = ""
    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isLoadingReplacement: Bool { emptyState == .loading && !resultsMatchQuery }
    private var resultsSubscription: AnyCancellable?
    private var statusSubscription: AnyCancellable?

    init(repository: any CatalogRepository, stores: [String: SearchStoreInfo] = [:], groupOrder: [String] = []) {
        self.repository = repository
        self.stores = stores
        groupRanks = Dictionary(groupOrder.enumerated().map { ($0.element.lowercased(), $0.offset) }, uniquingKeysWith: min)
        statusSubscription = repository.status.combineLatest(repository.cacheState)
            .map { CatalogEmptyState(status: $0, cacheState: $1) }
            .removeDuplicates()
            .sink { [weak self] state in
                self?.catalogEmptyState = state
                self?.updateEmptyState()
            }
        connectivitySubscription = repository.networkAvailable
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.normalizedQuery.isEmpty else { return }
                self.startSearch(debounce: false)
            }
        startSearch(debounce: false)
    }

    nonisolated deinit { searchTask?.cancel() }

    func refresh() async {
        guard canRefresh else { return }
        if !normalizedQuery.isEmpty { startSearch(debounce: false) }
        let pendingSearch = searchTask
        try? await repository.refresh()
        await pendingSearch?.value
    }

    private func startSearch(debounce: Bool) {
        searchTask?.cancel()
        resultsSubscription?.cancel()
        let query = normalizedQuery
        guard !query.isEmpty else {
            searchTask = nil
            setQueryFeedback(resultsMatchQuery ? nil : .loading)
            receive(.items(repository.observeProducts(matching: "")), for: query)
            return
        }
        if sections.isEmpty { setQueryFeedback(.loading) }
        searchTask = Task { [weak self, repository] in
            if debounce { try? await Task.sleep(for: .milliseconds(Const.searchDelay)) }
            guard !Task.isCancelled else { return }
            self?.setQueryFeedback(.loading)
            let result = await repository.searchProducts(matching: query)
            guard !Task.isCancelled else { return }
            self?.receive(result, for: query)
        }
    }

    private func receive(_ result: CatalogSearchResult, for query: String) {
        switch result {
        case .noServerMatches:
            display([], for: query, feedback: .empty)
        case .items(let publisher):
            resultsSubscription = publisher.sink { [weak self] items in
                self?.display(items, for: query, feedback: nil)
            }
        }
    }

    private func display(_ items: [CatalogItem], for query: String, feedback: CatalogEmptyState?) {
        displayedQuery = query
        self.items = items
        products = items.map(product)
        rebuildSections()
        setQueryFeedback(feedback)
    }

    private func setQueryFeedback(_ feedback: CatalogEmptyState?) {
        queryFeedback = feedback
        updateEmptyState()
    }

    private func updateEmptyState() {
        let state = queryFeedback ?? catalogEmptyState
        if emptyState != state { emptyState = state }
    }

    // MARK: - Presentation

    func showProduct(_ product: Product, storeID: String? = nil) {
        selectedProductStoreID = storeID
        selectedProduct = product
    }

    func alternatives(for productID: String, storeID: String?) async -> [Product] {
        await repository.alternativeProducts(for: productID, storeID: storeID,
                                             distances: stores.mapValues(\.distance), localOrder: priceOrder)
    }

    func dismissProduct() {
        selectedProduct = nil
    }

    private func rebuildSections() {
        switch mode {
        case .cheaper: sections = cheaperSections()
        case .faster: sections = fasterSections()
        }
    }

    private func cheaperSections() -> [SearchSection] {
        var groups: [String: (title: String, firstMatch: Int, products: [Product])] = [:]
        for (index, (item, product)) in zip(items, products).enumerated() {
            let title = Self.cleanedTitle(item.product.category)
                ?? Self.cleanedTitle(item.product.productType)
                ?? Self.cleanedTitle(product.displayName)
                ?? Texts.Catalog.uncategorized
            groups[title.lowercased(), default: (title, index, [])].products.append(product)
        }
        return groups.sorted { lhs, rhs in
            if !displayedQuery.isEmpty { return lhs.value.firstMatch < rhs.value.firstMatch }
            let lhsRank = groupRanks[lhs.key, default: Int.max]
            let rhsRank = groupRanks[rhs.key, default: Int.max]
            return lhsRank == rhsRank ? lhs.key < rhs.key : lhsRank < rhsRank
        }.map { id, group in
            SearchSection(id: id, title: group.title, address: nil, storeID: nil, walkingMinutes: nil,
                          products: group.products.sorted(by: priceOrder))
        }
    }

    private static func cleanedTitle(_ text: String?) -> String? {
        guard let text else { return nil }
        let title = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? nil : title
    }

    private func fasterSections() -> [SearchSection] {
        var byStore: [String: (firstMatch: Int, products: [Product])] = [:]
        for (index, product) in products.enumerated() {
            for offer in product.offers where offer.inStock != false {
                var scoped = product
                scoped.offers = [offer]
                byStore[offer.storeID, default: (index, [])].products.append(scoped)
            }
        }
        return byStore.sorted { lhs, rhs in
            if !displayedQuery.isEmpty, lhs.value.firstMatch != rhs.value.firstMatch {
                return lhs.value.firstMatch < rhs.value.firstMatch
            }
            let lhsTime = stores[lhs.key]?.walkingMinutes ?? Int.max
            let rhsTime = stores[rhs.key]?.walkingMinutes ?? Int.max
            return lhsTime == rhsTime ? lhs.key < rhs.key : lhsTime < rhsTime
        }.map { id, group in
            let offer = group.products.first?.offers.first
            return SearchSection(id: id, title: offer?.storeTitle ?? "", address: offer?.displayAddress, storeID: id,
                                 walkingMinutes: stores[id]?.walkingMinutes,
                                 products: group.products.sorted(by: priceOrder))
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
