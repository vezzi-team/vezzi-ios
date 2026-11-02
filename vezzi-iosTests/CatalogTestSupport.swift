import Combine
import CoreData
import XCTest
@testable import vezzi_ios

nonisolated enum CatalogFixtures {
    static let cachedAt = Date(timeIntervalSince1970: 1234)

    static func catalog(price: Decimal = Decimal(string: "99.90")!, date: Date? = Date(timeIntervalSince1970: 100)) -> CatalogImport {
        CatalogImport(products: [CatalogProduct(id: "p1", name: "Молоко", brand: "Brand", packageQuantity: 900, packageUnit: "мл")],
                      stores: [CatalogStore(id: "s1", name: "Store")],
                      offers: [CatalogOffer(id: "o1", productID: "p1", storeID: "s1", price: price,
                                            currency: "RUB", inStock: true, sourceUpdatedAt: date)])
    }

    static func cached(_ batch: CatalogImport = catalog(), at date: Date = cachedAt) -> CatalogCacheBatch {
        CatalogCacheBatch(import: batch, cachedAt: date)
    }

    static func snapshot(_ batch: CatalogImport = catalog()) throws -> CatalogSnapshot {
        try CatalogSnapshot().applying(cached(batch)).snapshot
    }

    static func largeCatalog() -> CatalogImport {
        CatalogImport(
            products: (0..<1000).map { CatalogProduct(id: "p\($0)", name: "Product \($0)", brand: "Brand", category: "Food") },
            stores: (0..<20).map { CatalogStore(id: "s\($0)", name: "Store \($0)") },
            offers: (0..<7868).map {
                CatalogOffer(id: "o\($0)", productID: "p\($0 % 1000)", storeID: "s\($0 % 20)", price: 100, currency: "RUB")
            }
        )
    }
}

@MainActor
extension XCTestCase {
    func catalogItems(
        from repository: any CatalogRepository,
        matching query: String = "",
        where predicate: @escaping ([CatalogItem]) -> Bool = { _ in true }
    ) async -> [CatalogItem] {
        await publishedItems(repository.observeProducts(matching: query), where: predicate)
    }

    func publishedItems(
        _ publisher: AnyPublisher<[CatalogItem], Never>,
        where predicate: @escaping ([CatalogItem]) -> Bool
    ) async -> [CatalogItem] {
        let received = expectation(description: "Expected catalog values are published")
        var result: [CatalogItem] = []
        let observation = publisher.filter(predicate).prefix(1).sink {
            result = $0
            received.fulfill()
        }
        defer { observation.cancel() }
        await fulfillment(of: [received], timeout: 5)
        return result
    }

    func closeStore(_ persistence: PersistenceController) throws {
        for store in persistence.container.persistentStoreCoordinator.persistentStores {
            try persistence.container.persistentStoreCoordinator.remove(store)
        }
    }
}

nonisolated struct FixedCatalogSource: CatalogSource {
    let batch: CatalogImport
    func loadCatalog() async throws -> CatalogImport { batch }
}

actor ControlledCatalogSource: CatalogSource {
    private var batch: CatalogImport?

    func succeed(with batch: CatalogImport) { self.batch = batch }

    func loadCatalog() async throws -> CatalogImport {
        guard let batch else { throw URLError(.notConnectedToInternet) }
        return batch
    }
}

@MainActor
final class ControlledCatalogCache: CatalogCache {
    var snapshot = CatalogSnapshot()
    var loadError: Error?
    var writeError: Error?
    var pauseLoad = false
    var pauseNextWrite = false
    var onLoadStarted: (() -> Void)?
    var onWriteStarted: (() -> Void)?
    var onSaved: (() -> Void)?
    private(set) var writes: [CatalogCacheBatch] = []
    private var loadContinuation: CheckedContinuation<CatalogSnapshot, Never>?
    private var writeContinuation: CheckedContinuation<Void, Never>?

    nonisolated deinit {}

    func loadSnapshot() async throws -> CatalogSnapshot {
        if let loadError { throw loadError }
        if pauseLoad {
            return await withCheckedContinuation {
                loadContinuation = $0
                onLoadStarted?()
            }
        }
        return snapshot
    }

    func finishLoading(_ stored: CatalogSnapshot) {
        snapshot = stored
        pauseLoad = false
        loadContinuation?.resume(returning: stored)
        loadContinuation = nil
    }

    func save(_ batch: CatalogCacheBatch) async throws {
        writes.append(batch)
        if pauseNextWrite {
            pauseNextWrite = false
            await withCheckedContinuation {
                writeContinuation = $0
                onWriteStarted?()
            }
        }
        if let writeError { throw writeError }
        snapshot = try snapshot.applying(batch).snapshot
        onSaved?()
    }

    func resumeWrite() {
        writeContinuation?.resume()
        writeContinuation = nil
    }
}

@MainActor
final class RecordingCatalogCache: CatalogCache {
    let storage: CoreDataCatalogCache
    var onSaved: (() -> Void)?
    private(set) var writes: [CatalogCacheBatch] = []

    init(storage: CoreDataCatalogCache) { self.storage = storage }
    nonisolated deinit {}

    func loadSnapshot() async throws -> CatalogSnapshot { try await storage.loadSnapshot() }

    func save(_ batch: CatalogCacheBatch) async throws {
        writes.append(batch)
        try await storage.save(batch)
        onSaved?()
    }
}
