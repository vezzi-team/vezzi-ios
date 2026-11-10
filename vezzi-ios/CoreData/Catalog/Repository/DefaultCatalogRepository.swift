import Combine
import Foundation
import OSLog

@MainActor
final class DefaultCatalogRepository: CatalogRepository {
    private let cache: (any CatalogCache)?
    private let source: (any CatalogSource)?
    private let session = CatalogSession()
    private let snapshot = CurrentValueSubject<CatalogSnapshot, Never>(CatalogSnapshot())
    private let cacheStatus: CurrentValueSubject<CatalogCacheState, Never>
    private let searchQueue = DispatchQueue(label: "Polka.CatalogSearch", qos: .userInitiated)
    private let logger = Logger(subsystem: "vezzi.vezzi-ios", category: "CatalogCache")
    private var cachePreparation: Task<Void, Never>?
    private var cacheWrite: Task<Void, Never>?
    private var refreshTask: Task<Void, Error>?
    private var refreshID = UUID()
    private var publishedRevision = 0
    private var pendingCacheIDs = CatalogRecordIDs()
    private var pendingReplacement = false
    private let catalogStatus = CurrentValueSubject<CatalogStatus, Never>(CatalogStatus())

    var canRefresh: Bool { source != nil }
    var cacheState: AnyPublisher<CatalogCacheState, Never> { cacheStatus.eraseToAnyPublisher() }
    var status: AnyPublisher<CatalogStatus, Never> { catalogStatus.eraseToAnyPublisher() }

    init(cache: (any CatalogCache)? = nil, source: (any CatalogSource)? = nil) {
        self.cache = cache
        self.source = source
        cacheStatus = CurrentValueSubject(cache == nil ? .disabled : .loading)
    }

    nonisolated deinit {}

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        observeItems { $0.items(matching: query) }
    }

    func observeAllProducts() -> AnyPublisher<[CatalogItem], Never> { observeItems { $0.allItems() } }

    func observeRelatedProducts(to productID: String, storeID: String?) -> AnyPublisher<[CatalogItem], Never> {
        observeItems { $0.relatedItems(to: productID, storeID: storeID) }
    }

    private func observeItems(_ query: @escaping @Sendable (CatalogSnapshot) -> [CatalogItem]) -> AnyPublisher<[CatalogItem], Never> {
        snapshot
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
        let id = UUID()
        refreshID = id
        let task = Task {
            catalogStatus.value.isRefreshing = true
            snapshot.send(snapshot.value.evaluated(at: Date()))
            defer { if refreshID == id { catalogStatus.value.isRefreshing = false } }
            do {
                let result = try await source.loadCatalog(ifNoneMatch: snapshot.value.metadata?.etag)
                try Task.checkCancellation()
                let update: CatalogSessionUpdate
                switch result {
                case .snapshot(let batch): update = try await session.replace(batch)
                case .notModified:
                    guard snapshot.value.metadata != nil else { throw APIError.invalidResponse }
                    update = await session.validate(at: Date())
                }
                try Task.checkCancellation()
                guard refreshID == id else { throw CancellationError() }
                accept(update)
                catalogStatus.value.failure = nil
                catalogStatus.value.isOffline = false
                scheduleCacheWrite()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !Task.isCancelled, refreshID == id else { throw CancellationError() }
                let failure = CatalogRefreshFailure.from(error)
                catalogStatus.value.failure = failure
                if failure == .offline { catalogStatus.value.isOffline = true }
                throw error
            }
        }
        refreshTask = task
        defer { if refreshID == id { refreshTask = nil } }
        try await task.value
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = UUID()
        catalogStatus.value.isRefreshing = false
    }

    func updateConnectivity(isConnected: Bool) {
        catalogStatus.value.isOffline = !isConnected
    }

    /// Cache opening and recovery never block source results or active queries.
    func prepareCache() async {
        guard let cache, cacheStatus.value != .available else { return }
        if let cachePreparation { return await cachePreparation.value }
        cacheStatus.send(.loading)
        let task = Task {
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
        await task.value
        cachePreparation = nil
    }

    private func accept(_ update: CatalogSessionUpdate) {
        if cache != nil {
            pendingCacheIDs.formUnion(update.changes)
            pendingReplacement = pendingReplacement || update.replacesCatalog
        }
        // Concurrent actor calls can resume on MainActor in a different order.
        guard update.revision > publishedRevision else { return }
        publishedRevision = update.revision
        snapshot.send(update.snapshot.evaluated(at: Date()))
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
            let batch = replacing ? snapshot.value.fullCacheBatch() : snapshot.value.cacheBatch(for: ids)
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
