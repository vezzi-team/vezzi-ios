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
    private var publishedRevision = 0
    private var pendingCacheIDs = CatalogRecordIDs()

    var canRefresh: Bool { source != nil }
    var cacheState: AnyPublisher<CatalogCacheState, Never> { cacheStatus.eraseToAnyPublisher() }

    init(cache: (any CatalogCache)? = nil, source: (any CatalogSource)? = nil) {
        self.cache = cache
        self.source = source
        cacheStatus = CurrentValueSubject(cache == nil ? .disabled : .loading)
    }

    nonisolated deinit {}

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        observeItems { $0.items(matching: query) }
    }

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
        let task = Task {
            let batch = try await source.loadCatalog()
            try await importCatalog(batch)
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
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
        if cache != nil { pendingCacheIDs.formUnion(update.changes) }
        // Concurrent actor calls can resume on MainActor in a different order.
        guard update.revision > publishedRevision else { return }
        publishedRevision = update.revision
        snapshot.send(update.snapshot)
    }

    private func scheduleCacheWrite() {
        guard cache != nil, cacheStatus.value == .available, cacheWrite == nil, !pendingCacheIDs.isEmpty else { return }
        cacheWrite = Task { [weak self] in await self?.writePendingChanges() }
    }

    private func writePendingChanges() async {
        defer { cacheWrite = nil }
        guard let cache else { return }
        while cacheStatus.value == .available, !pendingCacheIDs.isEmpty {
            let ids = pendingCacheIDs
            pendingCacheIDs = CatalogRecordIDs()
            let batch = snapshot.value.cacheBatch(for: ids)
            do {
                try await cache.save(batch)
            } catch {
                // Keep IDs, not an obsolete batch. Retry writes the newest session values.
                pendingCacheIDs.formUnion(ids)
                logger.error("Could not write catalog cache: \(String(describing: error), privacy: .private)")
                cacheStatus.send(.unavailable)
            }
        }
    }
}
