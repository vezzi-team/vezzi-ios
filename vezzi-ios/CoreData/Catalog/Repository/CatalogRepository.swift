import Combine
import Foundation

@MainActor
protocol CatalogRepository: AnyObject {
    var canRefresh: Bool { get }
    var cacheState: AnyPublisher<CatalogCacheState, Never> { get }

    /// Each subscription owns its query. Results are delivered on the main queue.
    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never>
    /// Accepts session changes. Optional cache writes are not a durability guarantee.
    func importCatalog(_ batch: CatalogImport) async throws
    func refresh() async throws
    func prepareCache() async
}

extension CatalogRepository {
    var cacheState: AnyPublisher<CatalogCacheState, Never> {
        Just(.disabled).eraseToAnyPublisher()
    }

    func prepareCache() async {}
}

nonisolated enum CatalogCacheState: Equatable, Sendable {
    case disabled
    case loading
    case available
    case unavailable
}

/// Optional persistence. Failure must not prevent the repository from using source data.
@MainActor
protocol CatalogCache: AnyObject {
    func loadSnapshot() async throws -> CatalogSnapshot
    func save(_ batch: CatalogCacheBatch) async throws
}

/// A future API or file adapter maps its input into the application's import model.
nonisolated protocol CatalogSource: Sendable {
    func loadCatalog() async throws -> CatalogImport
}

nonisolated enum CatalogError: Error, Equatable {
    case invalidRecord(entity: String, id: String)
    case duplicateID(entity: String, id: String)
    case missingReference(offerID: String)
    case sourceUnavailable
}
