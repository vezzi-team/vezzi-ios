import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var items: [CatalogItem] = []
    @Published private(set) var refreshErrorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCacheUnavailable = false

    var canRefresh: Bool { repository.canRefresh }
    var isResultLimitReached: Bool { items.count == CatalogSearch.resultLimit }

    private let repository: any CatalogRepository
    private var querySubscription: AnyCancellable?
    private var resultsSubscription: AnyCancellable?
    private var cacheSubscription: AnyCancellable?

    init(repository: any CatalogRepository) {
        self.repository = repository
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
                self?.items = items
            }
    }

    private enum Const {
        static let searchDelay = 250
    }
}
