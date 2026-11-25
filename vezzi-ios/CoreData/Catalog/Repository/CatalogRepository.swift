import Combine
import Foundation

@MainActor
protocol CatalogRepository: AnyObject {
    var canRefresh: Bool { get }
    var cacheState: AnyPublisher<CatalogCacheState, Never> { get }
    var status: AnyPublisher<CatalogStatus, Never> { get }
    var networkAvailable: AnyPublisher<Bool, Never> { get }

    /// Each subscription owns its query. Results are delivered on the main queue.
    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never>
    /// Resolves the text once, then observes catalog prices and stores for those matches.
    func searchProducts(matching query: String) async -> CatalogSearchResult
    func observeAllProducts() -> AnyPublisher<[CatalogItem], Never>
    /// Store identities are independent of products and of which offers are in stock.
    func observeStoreLogoURLs() -> AnyPublisher<[String: URL], Never>
    /// Prefers server-ranked alternatives and uses the local group when offline or no match fits the scope.
    /// A store scope includes only that store's offers for products not marked out of stock there.
    func observeRelatedProducts(to productID: String, storeID: String?) async -> AnyPublisher<CatalogAlternatives, Never>
    /// Accepts session changes. Optional cache writes are not a durability guarantee.
    func importCatalog(_ batch: CatalogImport) async throws
    func refresh() async throws
    func prepareCache() async
}

extension CatalogRepository {
    var networkAvailable: AnyPublisher<Bool, Never> { Just(true).eraseToAnyPublisher() }

    func searchProducts(matching query: String) async -> CatalogSearchResult {
        .items(observeProducts(matching: query))
    }

    var status: AnyPublisher<CatalogStatus, Never> { Just(CatalogStatus()).eraseToAnyPublisher() }
    func observeAllProducts() -> AnyPublisher<[CatalogItem], Never> { observeProducts(matching: "") }
    var cacheState: AnyPublisher<CatalogCacheState, Never> {
        Just(.disabled).eraseToAnyPublisher()
    }

    func prepareCache() async {}
}

enum CatalogSearchResult {
    case noServerMatches
    case items(AnyPublisher<[CatalogItem], Never>)
}

nonisolated enum CatalogAlternatives: Equatable, Sendable {
    case ranked([CatalogItem])
    case local([CatalogItem])

    var items: [CatalogItem] {
        switch self {
        case .ranked(let items), .local(let items): items
        }
    }
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
    func loadCatalog(ifNoneMatch: String?) async throws -> CatalogSourceResult
}

nonisolated protocol CatalogProductSearching: Sendable {
    func searchProducts(matching query: String) async throws -> [CatalogProduct]
}

nonisolated protocol CatalogAnalogProviding: Sendable {
    func analogs(for productID: String) async throws -> [CatalogProduct]
}

nonisolated enum CatalogError: Error, Equatable {
    case invalidRecord(entity: String, id: String)
    case duplicateID(entity: String, id: String)
    case missingReference(offerID: String)
    case sourceUnavailable
}
