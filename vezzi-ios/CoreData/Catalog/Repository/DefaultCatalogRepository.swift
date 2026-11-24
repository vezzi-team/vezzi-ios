import Combine
import Foundation
import OSLog
import Synchronization

@MainActor
final class DefaultCatalogRepository: CatalogRepository {
    private let cache: (any CatalogCache)?
    private let source: (any CatalogSource)?
    private let session = CatalogSession()
    private let publications = CurrentValueSubject<PublishedSnapshot, Never>(PublishedSnapshot(CatalogSnapshot()))
    private var snapshot: CatalogSnapshot { publications.value.snapshot }
    private let cacheStatus: CurrentValueSubject<CatalogCacheState, Never>
    private let searchQueue = DispatchQueue(label: "Polka.CatalogSearch", qos: .userInitiated)
    private let logger = Logger(subsystem: "vezzi.vezzi-ios", category: "CatalogCache")
    private var cachePreparation: Task<Void, Never>?
    private var cacheWrite: Task<Void, Never>?
    private var refreshTask: Task<Void, Error>?
    private var hasCheckedInitialCache = false
    private var publishedRevision = 0
    private var pendingCacheIDs = CatalogRecordIDs()
    private var pendingReplacement = false
    private let catalogStatus = CurrentValueSubject<CatalogStatus, Never>(CatalogStatus())
    private let networkPath = CurrentValueSubject<Bool, Never>(true)

    var canRefresh: Bool { source != nil }
    var cacheState: AnyPublisher<CatalogCacheState, Never> { cacheStatus.eraseToAnyPublisher() }
    var status: AnyPublisher<CatalogStatus, Never> { catalogStatus.eraseToAnyPublisher() }
    var networkAvailable: AnyPublisher<Bool, Never> { networkPath.eraseToAnyPublisher() }

    init(cache: (any CatalogCache)? = nil, source: (any CatalogSource)? = nil) {
        self.cache = cache
        self.source = source
        cacheStatus = CurrentValueSubject(cache == nil ? .disabled : .loading)
    }

    nonisolated deinit {}

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        observeItems { $0.snapshot.items(matching: query) }
    }

    func searchProducts(matching query: String) async -> CatalogSearchResult {
        if let search = source as? any CatalogProductSearching, networkPath.value,
           !query.isEmpty, query.unicodeScalars.count <= CatalogSearch.serverQueryLimit,
           let matches = try? await search.searchProducts(matching: query) {
            guard !matches.isEmpty else { return .noServerMatches }
            return .items(observeItems { $0.snapshot.items(for: matches) })
        }
        return .items(observeProducts(matching: query))
    }

    func observeAllProducts() -> AnyPublisher<[CatalogItem], Never> { observeItems { $0.allItems() } }

    func observeRelatedProducts(to productID: String, storeID: String?) async -> AnyPublisher<CatalogAlternatives, Never> {
        var matches: [CatalogProduct] = []
        if let provider = source as? any CatalogAnalogProviding, networkPath.value {
            do {
                matches = try await provider.analogs(for: productID)
            } catch let error as URLError where error.code != .cancelled {
                // A transport failure can precede the path monitor's update.
            } catch APIError.http(let status, _, _, _) where status == 408 || status == 429 || (500..<600).contains(status) {
                // The endpoint is temporarily unavailable. Resolve this page from the catalog.
            } catch {
                return Empty().eraseToAnyPublisher()
            }
        }
        guard !Task.isCancelled else { return Empty().eraseToAnyPublisher() }
        if cacheStatus.value == .loading { startCachePreparation() }
        let loading = cacheStatus.combineLatest(catalogStatus, networkPath)
            .map { cache, status, connected in
                (cache == .loading && !status.hasSnapshot) || (status.isRefreshing && connected)
            }
            .removeDuplicates()
        return publications.combineLatest(loading)
            .receive(on: searchQueue)
            .compactMap { @Sendable [matches] publication, loading -> CatalogAlternatives? in
                let snapshot = publication.snapshot
                // A detail page keeps its first result. Wait for missing catalog records before joining offers.
                if loading && matches.contains(where: { snapshot.products[$0.id] == nil }) { return nil }
                let ranked = snapshot.items(for: matches).compactMap { $0.scoped(to: storeID) }
                if !ranked.isEmpty { return .ranked(ranked) }
                let local = snapshot.relatedItems(to: productID, storeID: storeID)
                return loading && local.isEmpty ? nil : .local(local)
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private func observeItems(_ query: @escaping @Sendable (PublishedSnapshot) -> [CatalogItem]) -> AnyPublisher<[CatalogItem], Never> {
        publications
            .receive(on: searchQueue)
            .map(query)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func importCatalog(_ batch: CatalogImport) async throws {
        let update = try await session.apply(batch, at: Date())
        accept(update)
        scheduleCacheWrite()
    }

    func refresh() async throws {
        if let refreshTask { return try await refreshTask.value }
        guard let source else { throw CatalogError.sourceUnavailable }
        let task = Task {
            publications.send(PublishedSnapshot(snapshot.evaluated(at: Date())))
            defer {
                refreshTask = nil
                catalogStatus.value.isRefreshing = false
            }
            do {
                await waitForInitialCache()
                let result = try await source.loadCatalog(ifNoneMatch: snapshot.metadata?.etag)
                try Task.checkCancellation()
                let update: CatalogSessionUpdate
                switch result {
                case .snapshot(let batch): update = try await session.replace(batch)
                case .notModified:
                    guard snapshot.metadata != nil else { throw APIError.invalidResponse }
                    update = await session.validate(at: Date())
                }
                try Task.checkCancellation()
                accept(update)
                catalogStatus.value.failure = nil
                catalogStatus.value.isOffline = false
                scheduleCacheWrite()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let failure = CatalogRefreshFailure.from(error)
                catalogStatus.value.failure = failure
                if failure == .offline { catalogStatus.value.isOffline = true }
                throw error
            }
        }
        refreshTask = task
        catalogStatus.value.isRefreshing = true
        try await task.value
    }

    func updateConnectivity(isConnected: Bool) {
        catalogStatus.value.isOffline = !isConnected
        guard networkPath.value != isConnected else { return }
        networkPath.send(isConnected)
        guard isConnected, source != nil, refreshTask != nil || catalogStatus.value.failure != nil else { return }
        // The reconnect can arrive before the interrupted export reports its failure.
        let pending = refreshTask
        Task {
            try? await pending?.value
            guard networkPath.value, catalogStatus.value.failure != nil else { return }
            try? await refresh()
        }
    }

    private func waitForInitialCache() async {
        guard !hasCheckedInitialCache else { return }
        hasCheckedInitialCache = true
        guard cacheStatus.value == .loading else { return }

        startCachePreparation()
        // A slow disk read continues even if the first export has to start without an ETag.
        let readiness = cacheStatus.first { $0 != .loading }
            .timeout(.milliseconds(500), scheduler: DispatchQueue.main)
        var iterator = readiness.values.makeAsyncIterator()
        _ = await iterator.next()
    }

    func prepareCache() async {
        await startCachePreparation()?.value
    }

    @discardableResult
    private func startCachePreparation() -> Task<Void, Never>? {
        guard let cache, cacheStatus.value != .available else { return nil }
        if let cachePreparation { return cachePreparation }
        cacheStatus.send(.loading)
        let task = Task {
            defer { cachePreparation = nil }
            do {
                let stored = try await cache.loadSnapshot()
                accept(await session.mergeCache(stored))
                cacheStatus.send(.available)
                scheduleCacheWrite()
            } catch {
                logger.error("Could not read catalog cache: \(String(describing: error), privacy: .private)")
                cacheStatus.send(.unavailable)
            }
        }
        cachePreparation = task
        return task
    }

    private func accept(_ update: CatalogSessionUpdate) {
        if cache != nil {
            pendingCacheIDs.formUnion(update.changes)
            pendingReplacement = pendingReplacement || update.replacesCatalog
        }
        // Concurrent actor calls can resume on MainActor in a different order.
        guard update.revision > publishedRevision else { return }
        publishedRevision = update.revision
        publications.send(PublishedSnapshot(update.snapshot.evaluated(at: Date())))
        var status = catalogStatus.value
        status.hasSnapshot = update.snapshot.metadata != nil || !update.snapshot.products.isEmpty
        status.isSynthetic = update.snapshot.metadata?.isSynthetic ?? false
        status.validatedAt = update.snapshot.metadata?.validatedAt
        catalogStatus.send(status)
    }

    private func scheduleCacheWrite() {
        guard cache != nil, cacheStatus.value == .available, cacheWrite == nil,
              pendingReplacement || !pendingCacheIDs.isEmpty else { return }
        cacheWrite = Task { [weak self] in await self?.writePendingChanges() }
    }

    private func writePendingChanges() async {
        defer { cacheWrite = nil }
        guard let cache else { return }
        while cacheStatus.value == .available, pendingReplacement || !pendingCacheIDs.isEmpty {
            let ids = pendingCacheIDs
            let replacing = pendingReplacement
            pendingCacheIDs = CatalogRecordIDs()
            pendingReplacement = false
            let batch = replacing ? snapshot.fullCacheBatch() : snapshot.cacheBatch(for: ids)
            do {
                try await cache.save(batch)
            } catch {
                // Keep IDs, not an obsolete batch. Retry writes the newest session values.
                pendingCacheIDs.formUnion(ids)
                pendingReplacement = pendingReplacement || replacing
                logger.error("Could not write catalog cache: \(String(describing: error), privacy: .private)")
                cacheStatus.send(.unavailable)
            }
        }
    }
}

/// All subscribers to the same publication reuse its full list. A new publication
/// starts with an empty cache, including when only the price evaluation date changes.
nonisolated private final class PublishedSnapshot: Sendable {
    let snapshot: CatalogSnapshot
    private let cachedItems = Mutex<[CatalogItem]?>(nil)

    init(_ snapshot: CatalogSnapshot) {
        self.snapshot = snapshot
    }

    func allItems() -> [CatalogItem] {
        cachedItems.withLock { cached in
            if let cached { return cached }
            let items = snapshot.allItems()
            cached = items
            return items
        }
    }
}
