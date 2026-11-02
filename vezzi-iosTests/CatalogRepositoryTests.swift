import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class CatalogRepositoryTests: XCTestCase {
    func testOfferOnlyUpdateReachesExistingSubscription() async throws {
        let repository = DefaultCatalogRepository()
        try await repository.importCatalog(CatalogFixtures.catalog())
        let changed = expectation(description: "Updated price reaches the existing query")
        let observation = repository.observeProducts(matching: "молоко")
            .filter { $0.first?.offers.first?.offer.price == 120 }.prefix(1).sink { _ in changed.fulfill() }
        defer { observation.cancel() }
        let offers = CatalogFixtures.catalog(price: 120, date: Date(timeIntervalSince1970: 200)).offers
        try await repository.importCatalog(CatalogImport(offers: offers))
        await fulfillment(of: [changed], timeout: 5)
    }

    func testStoreChangesAndDeactivationReachExistingSubscription() async throws {
        let repository = DefaultCatalogRepository()
        try await repository.importCatalog(CatalogFixtures.catalog())
        let renamed = expectation(description: "Store name changes")
        let hidden = expectation(description: "Inactive store offers disappear")
        var didRename = false
        let observation = repository.observeProducts(matching: "").sink { items in
            if items.first?.offers.first?.store.name == "Changed", !didRename {
                didRename = true
                renamed.fulfill()
            }
            if didRename, items.first?.offers.isEmpty == true { hidden.fulfill() }
        }
        defer { observation.cancel() }
        try await repository.importCatalog(CatalogImport(stores: [CatalogStore(id: "s1", name: "Changed")]))
        await fulfillment(of: [renamed], timeout: 5)
        try await repository.importCatalog(CatalogImport(stores: [CatalogStore(id: "s1", name: "Changed", isActive: false)]))
        await fulfillment(of: [hidden], timeout: 5)
    }

    func testQueriesAreIndependentAndCancellationDoesNotAffectAnotherQuery() async throws {
        let repository = DefaultCatalogRepository()
        var batch = CatalogFixtures.catalog()
        batch.products.append(CatalogProduct(id: "p2", name: "Bread"))
        try await repository.importCatalog(batch)
        let milk = expectation(description: "Milk query")
        let bread = expectation(description: "Bread query survives other cancellation")
        let first = repository.observeProducts(matching: "МОЛОКО").filter { !$0.isEmpty }.prefix(1).sink { items in
            XCTAssertEqual(items.map(\.id), ["p1"])
            milk.fulfill()
        }
        let second = repository.observeProducts(matching: "bread").filter { $0.first?.product.brand == "Fresh" }.prefix(1).sink { items in
            XCTAssertEqual(items.map(\.id), ["p2"])
            bread.fulfill()
        }
        defer { first.cancel(); second.cancel() }
        await fulfillment(of: [milk], timeout: 5)
        first.cancel()
        try await repository.importCatalog(CatalogImport(products: [CatalogProduct(id: "p2", name: "Bread", brand: "Fresh")]))
        await fulfillment(of: [bread], timeout: 5)
    }

    func testSearchUsesAllWordsAcrossFieldsAndHonorsLimit() async throws {
        let repository = DefaultCatalogRepository()
        var batch = CatalogFixtures.largeCatalog()
        batch.products.append(CatalogProduct(id: "special", name: "Café", brand: "Brand", category: "Drinks"))
        try await repository.importCatalog(batch)
        let all = await catalogItems(from: repository)
        XCTAssertEqual(all.count, CatalogSearch.resultLimit)
        let filtered = await catalogItems(from: repository, matching: "  CAFE  drinks  BRAND ")
        XCTAssertEqual(filtered.map(\.id), ["special"])
        let none = await catalogItems(from: repository, matching: "missing")
        XCTAssertTrue(none.isEmpty)
    }

    func testReassigningOfferUpdatesProductIndex() async throws {
        let repository = DefaultCatalogRepository()
        var batch = CatalogFixtures.catalog()
        batch.products.append(CatalogProduct(id: "p2", name: "Bread"))
        try await repository.importCatalog(batch)
        let offer = CatalogOffer(id: "o1", productID: "p2", storeID: "s1", price: 120, currency: "RUB",
                                 sourceUpdatedAt: Date(timeIntervalSince1970: 200))
        try await repository.importCatalog(CatalogImport(offers: [offer]))
        let items = await catalogItems(from: repository)
        XCTAssertTrue(items.first { $0.id == "p1" }!.offers.isEmpty)
        XCTAssertEqual(items.first { $0.id == "p2" }?.offers.map(\.id), ["o1"])
    }

    func testInvalidImportIsAtomicWithoutCache() async throws {
        let repository = DefaultCatalogRepository()
        try await repository.importCatalog(CatalogFixtures.catalog())
        let invalid = CatalogImport(products: [CatalogProduct(id: "p2", name: "Must roll back")], offers: [
            CatalogOffer(id: "bad", productID: "p2", storeID: "missing", price: 100, currency: "RUB")
        ])
        do {
            try await repository.importCatalog(invalid)
            XCTFail("A missing reference must reject the complete batch")
        } catch { XCTAssertEqual(error as? CatalogError, .missingReference(offerID: "bad")) }
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.map(\.id), ["p1"])
    }

    func testConcurrentImportsDoNotLoseProducts() async throws {
        let repository = DefaultCatalogRepository()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    try await repository.importCatalog(CatalogImport(products: [CatalogProduct(id: "p\(index)", name: "Product \(index)")]))
                }
            }
            try await group.waitForAll()
        }
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.count, 30)
    }

    func testOlderAndUndatedOffersCannotOverwriteNewerSessionPrice() async throws {
        let repository = DefaultCatalogRepository()
        try await repository.importCatalog(CatalogFixtures.catalog(price: 120, date: Date(timeIntervalSince1970: 200)))
        try await repository.importCatalog(CatalogFixtures.catalog(price: 90))
        try await repository.importCatalog(CatalogFixtures.catalog(price: 80, date: nil))
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.first?.offers.first?.offer.price, 120)
    }

    func testSourceWorksWithoutCache() async throws {
        let repository = DefaultCatalogRepository(source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        try await repository.refresh()
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.map(\.id), ["p1"])
    }

    func testCacheOpeningFailureDoesNotBlockSource() async throws {
        let cache = ControlledCatalogCache()
        cache.loadError = URLError(.cannotOpenFile)
        let dependencies = AppDependencies(cache: cache, source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        await dependencies.load()
        try await dependencies.catalog.refresh()
        let items = await catalogItems(from: dependencies.catalog)
        XCTAssertEqual(items.map(\.id), ["p1"])
    }

    func testSlowCacheDoesNotDelayOrRollBackSourceResults() async throws {
        let cache = ControlledCatalogCache()
        cache.pauseLoad = true
        let started = expectation(description: "Cache load started")
        cache.onLoadStarted = { started.fulfill() }
        var fresh = CatalogFixtures.catalog(price: 120, date: Date(timeIntervalSince1970: 200))
        fresh.products[0].name = "Fresh product"
        let repository = DefaultCatalogRepository(cache: cache, source: FixedCatalogSource(batch: fresh))
        let preparing = Task { await repository.prepareCache() }
        await fulfillment(of: [started], timeout: 5)
        try await repository.refresh()
        let before = await catalogItems(from: repository)
        XCTAssertEqual(before.first?.product.name, "Fresh product")
        cache.finishLoading(try CatalogFixtures.snapshot(CatalogFixtures.catalog(price: 90)))
        await preparing.value
        let after = await catalogItems(from: repository)
        XCTAssertEqual(after.first?.product.name, "Fresh product")
        XCTAssertEqual(after.first?.offers.first?.offer.price, 120)
    }

    func testNewerCachedOfferWinsOverOlderSource() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogFixtures.snapshot(CatalogFixtures.catalog(price: 150, date: Date(timeIntervalSince1970: 300)))
        let repository = DefaultCatalogRepository(cache: cache)
        try await repository.importCatalog(CatalogFixtures.catalog(price: 90))
        await repository.prepareCache()
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.first?.offers.first?.offer.price, 150)
    }

    func testRetryKeepsSubscriptionsAndSavesLatestSessionValues() async throws {
        let cache = ControlledCatalogCache()
        cache.writeError = URLError(.cannotWriteToFile)
        let repository = DefaultCatalogRepository(cache: cache)
        await repository.prepareCache()
        let failed = expectation(description: "Cache failure reported")
        let status = repository.cacheState.filter { $0 == .unavailable }.prefix(1).sink { _ in failed.fulfill() }
        defer { status.cancel() }
        try await repository.importCatalog(CatalogFixtures.catalog(price: 120))
        await fulfillment(of: [failed], timeout: 5)
        let updated = expectation(description: "Existing query survives recovery")
        let observation = repository.observeProducts(matching: "").filter { $0.first?.offers.first?.offer.price == 140 }
            .prefix(1).sink { _ in updated.fulfill() }
        defer { observation.cancel() }
        try await repository.importCatalog(CatalogImport(offers: CatalogFixtures.catalog(price: 140).offers))
        let saved = expectation(description: "Latest data persisted")
        cache.onSaved = { saved.fulfill() }
        cache.writeError = nil
        await repository.prepareCache()
        await fulfillment(of: [updated, saved], timeout: 5)
        XCTAssertEqual(cache.snapshot.offers["o1"]?.offer.price, 140)
    }

    func testBurstUpdatesCoalesceWhileDiskWriteIsInFlight() async throws {
        let cache = ControlledCatalogCache()
        let batch = CatalogFixtures.largeCatalog()
        cache.snapshot = try CatalogFixtures.snapshot(batch)
        let repository = DefaultCatalogRepository(cache: cache)
        await repository.prepareCache()
        cache.pauseNextWrite = true
        let started = expectation(description: "First write is in flight")
        cache.onWriteStarted = { started.fulfill() }
        var first = batch.offers[0]
        first.price = 200
        try await repository.importCatalog(CatalogImport(offers: [first]))
        await fulfillment(of: [started], timeout: 5)
        for index in 0..<10 {
            var offer = batch.offers[index]
            offer.price = Decimal(300 + index)
            try await repository.importCatalog(CatalogImport(offers: [offer]))
        }
        XCTAssertEqual(cache.writes.count, 1)
        let saved = expectation(description: "Only one combined pending write follows")
        saved.expectedFulfillmentCount = 2
        cache.onSaved = { saved.fulfill() }
        cache.resumeWrite()
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertEqual(cache.writes.count, 2)
        XCTAssertEqual(cache.writes.map { $0.offers.count }, [1, 10])
        XCTAssertEqual(cache.writes.reduce(0) { $0 + $1.products.count }, 11)
        XCTAssertEqual(cache.snapshot.offers[first.id]?.offer.price, 300)
        XCTAssertEqual(cache.snapshot.offers[batch.offers[9].id]?.offer.price, 309)
    }

    func testConcurrentSessionChangesAreAllPersisted() async throws {
        let cache = ControlledCatalogCache()
        let repository = DefaultCatalogRepository(cache: cache)
        await repository.prepareCache()
        let saved = expectation(description: "All concurrent changes reach the cache")
        var completed = false
        cache.onSaved = {
            if cache.snapshot.products.count == 30, !completed {
                completed = true
                saved.fulfill()
            }
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    let product = CatalogProduct(id: "p\(index)", name: "Product \(index)")
                    try await repository.importCatalog(CatalogImport(products: [product]))
                }
            }
            try await group.waitForAll()
        }
        await fulfillment(of: [saved], timeout: 5)
        let items = await catalogItems(from: repository)
        XCTAssertEqual(Set(items.map(\.id)), Set(cache.snapshot.products.keys))
    }

    func testFailedInFlightWriteRetainsNewerPendingChangesForRetry() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogFixtures.snapshot()
        let repository = DefaultCatalogRepository(cache: cache)
        await repository.prepareCache()
        cache.pauseNextWrite = true
        cache.writeError = URLError(.cannotWriteToFile)
        let started = expectation(description: "Old value write is paused")
        cache.onWriteStarted = { started.fulfill() }
        try await repository.importCatalog(CatalogImport(offers: CatalogFixtures.catalog(price: 120).offers))
        await fulfillment(of: [started], timeout: 5)
        try await repository.importCatalog(CatalogImport(offers: CatalogFixtures.catalog(price: 140).offers))
        let failed = expectation(description: "In-flight write fails")
        let status = repository.cacheState.filter { $0 == .unavailable }.prefix(1).sink { _ in failed.fulfill() }
        defer { status.cancel() }
        cache.resumeWrite()
        await fulfillment(of: [failed], timeout: 5)
        cache.writeError = nil
        let saved = expectation(description: "Retry saves the latest value")
        cache.onSaved = { saved.fulfill() }
        await repository.prepareCache()
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertEqual(cache.writes.count, 2)
        XCTAssertEqual(cache.writes.last?.offers.first?.offer.price, 140)
        XCTAssertEqual(cache.snapshot.offers["o1"]?.offer.price, 140)
    }

    func testStoreOnlyUpdateDoesNotRewriteOfferOrChangeCachedAt() async throws {
        let persistence = PersistenceController(inMemory: true)
        let storage = CoreDataCatalogCache(persistence: persistence)
        try await storage.save(CatalogFixtures.cached())
        let cache = RecordingCatalogCache(storage: storage)
        let repository = DefaultCatalogRepository(cache: cache)
        await repository.prepareCache()
        let saved = expectation(description: "Store update saved")
        cache.onSaved = { saved.fulfill() }
        try await repository.importCatalog(CatalogImport(stores: [CatalogStore(id: "s1", name: "Changed")]))
        await fulfillment(of: [saved], timeout: 5)
        let stored = try await storage.loadSnapshot()
        let items = await catalogItems(from: repository)
        XCTAssertEqual(cache.writes.count, 1)
        XCTAssertTrue(cache.writes[0].offers.isEmpty)
        XCTAssertEqual(stored.offers["o1"]?.cachedAt, CatalogFixtures.cachedAt)
        XCTAssertEqual(items.first?.offers.first?.cachedAt, CatalogFixtures.cachedAt)
    }
}
