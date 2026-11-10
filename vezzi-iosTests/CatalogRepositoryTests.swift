import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class CatalogRepositoryTests: XCTestCase {
    func testFullSnapshotRemovesMissingRecordsEvenWhenOldCacheArrivesLate() async throws {
        let cache = ControlledCatalogCache()
        cache.pauseLoad = true
        let started = expectation(description: "Cache loading")
        cache.onLoadStarted = { started.fulfill() }
        let repository = DefaultCatalogRepository(cache: cache, source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        let loading = Task { await repository.prepareCache() }
        await fulfillment(of: [started], timeout: 5)
        try await repository.refresh()
        var obsolete = CatalogFixtures.catalog()
        obsolete.products.append(CatalogProduct(id: "deleted", name: "Deleted"))
        cache.finishLoading(try CatalogFixtures.snapshot(obsolete))
        await loading.value
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.map(\.id), ["p1"])
        let saved = expectation(description: "Replacement saved")
        if cache.snapshot.metadata != nil { saved.fulfill() } else { cache.onSaved = { saved.fulfill() } }
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertNil(cache.snapshot.products["deleted"])
        XCTAssertEqual(cache.snapshot.metadata?.importID, 1)
    }

    func testOfflineRefreshPreservesSnapshotAndSharedStatusRecovers() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogSnapshot().applying(CatalogFixtures.export()).snapshot
        let source = ControlledCatalogSource()
        let repository = DefaultCatalogRepository(cache: cache, source: source)
        let home = HomeViewModel(repository: repository)
        let search = SearchViewModel(repository: repository)
        await repository.prepareCache()
        await home.refresh()
        XCTAssertEqual(home.catalogStatus.failure, .offline)
        XCTAssertEqual(search.catalogStatus.failure, .offline)
        XCTAssertTrue(home.catalogStatus.hasSnapshot)
        XCTAssertTrue(home.catalogStatus.isOffline)
        let saved = await catalogItems(from: repository)
        XCTAssertEqual(saved.map(\.id), ["p1"])
        await source.succeed(with: CatalogFixtures.catalog(price: 150))
        await search.refresh()
        XCTAssertNil(home.catalogStatus.failure)
        XCTAssertFalse(home.catalogStatus.isOffline)
        let updated = await catalogItems(from: repository)
        XCTAssertEqual(updated.first?.offers.first?.offer.price, 150)
    }

    func testConditionalRefreshSharesOneRequestAndPreservesOfferReceiptTime() async throws {
        let original = CatalogFixtures.export(date: Date(timeIntervalSince1970: 1234))
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogSnapshot().applying(original).snapshot
        let source = ConditionalCatalogSource()
        let repository = DefaultCatalogRepository(cache: cache, source: source)
        await repository.prepareCache()
        async let first: Void = repository.refresh()
        async let second: Void = repository.refresh()
        _ = try await (first, second)
        let headers = await source.headers
        XCTAssertEqual(headers, ["\"1\""])
        let items = await catalogItems(from: repository)
        XCTAssertEqual(items.first?.offers.first?.cachedAt, Date(timeIntervalSince1970: 1234))
        XCTAssertFalse(items.first?.offers.first?.isFresh ?? true)
        var status = CatalogStatus()
        let observation = repository.status.sink { status = $0 }
        defer { observation.cancel() }
        XCTAssertGreaterThan(status.validatedAt ?? .distantPast, Date(timeIntervalSince1970: 1234))
        XCTAssertNil(status.failure)
    }

    func testFailedReplacementRetriesTheLatestWholeSnapshot() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogFixtures.snapshot(CatalogImport(products: [CatalogProduct(id: "old", name: "Old")]))
        cache.writeError = URLError(.cannotWriteToFile)
        let source = ControlledCatalogSource()
        await source.succeed(with: CatalogFixtures.catalog())
        let repository = DefaultCatalogRepository(cache: cache, source: source)
        await repository.prepareCache()
        let failed = expectation(description: "Write failed")
        let observation = repository.cacheState.filter { $0 == .unavailable }.prefix(1).sink { _ in failed.fulfill() }
        defer { observation.cancel() }
        try await repository.refresh()
        await fulfillment(of: [failed], timeout: 5)
        await source.succeed(with: CatalogFixtures.catalog(price: 200))
        try await repository.refresh()
        cache.writeError = nil
        let saved = expectation(description: "Latest replacement saved")
        cache.onSaved = { saved.fulfill() }
        await repository.prepareCache()
        await fulfillment(of: [saved], timeout: 5)
        XCTAssertNil(cache.snapshot.products["old"])
        XCTAssertEqual(cache.snapshot.offers["o1"]?.offer.price, 200)
    }

    func testCancelledRefreshCannotOverwriteTheNextSuccessfulStatus() async throws {
        let source = LateFailureCatalogSource()
        let repository = DefaultCatalogRepository(source: source)
        let old = Task { try await repository.refresh() }
        for _ in 0..<100 {
            if await source.hasStarted { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        repository.cancelRefresh()
        try await repository.refresh()
        await source.releaseFailure()
        do { try await old.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        var status = CatalogStatus()
        let observation = repository.status.sink { status = $0 }
        defer { observation.cancel() }
        XCTAssertNil(status.failure)
        XCTAssertFalse(status.isOffline)
        XCTAssertFalse(status.isRefreshing)
        XCTAssertTrue(status.hasSnapshot)
    }

    func testRelatedProductsAreIndependentOfTheTextSearchLimit() async throws {
        let repository = DefaultCatalogRepository()
        var batch = CatalogImport(products: (0..<CatalogSearch.resultLimit).map {
            CatalogProduct(id: "other-\($0)", name: "A product \($0)", productType: "other")
        })
        batch.products += [
            CatalogProduct(id: "selected", name: "Z selected milk", productType: "milk"),
            CatalogProduct(id: "alternative-1", name: "Z alternative one", productType: "milk"),
            CatalogProduct(id: "alternative-2", name: "Z alternative two", productType: "milk")
        ]
        try await repository.importCatalog(batch)
        let limited = await catalogItems(from: repository)
        XCTAssertEqual(limited.count, CatalogSearch.resultLimit)
        XCTAssertTrue(limited.allSatisfy { $0.id.hasPrefix("other-") })
        let textResults = await catalogItems(from: repository, matching: "selected")
        XCTAssertEqual(textResults.map(\.id), ["selected"])
        let related = await publishedItems(repository.observeRelatedProducts(to: "selected", storeID: nil), where: { $0.count == 2 })
        XCTAssertEqual(related.map(\.id), ["alternative-1", "alternative-2"])

        let snapshot = try CatalogFixtures.snapshot(batch)
        let previewRelated = await publishedItems(PreviewCatalogRepository(snapshot: snapshot)
            .observeRelatedProducts(to: "selected", storeID: nil), where: { $0.count == 2 })
        XCTAssertEqual(previewRelated, related)
    }

    func testRelatedQueryTracksOffersAndGroupChanges() async throws {
        let repository = DefaultCatalogRepository()
        var batch = CatalogFixtures.catalog()
        batch.products[0].productType = "milk"
        batch.products.append(CatalogProduct(id: "alternative", name: "Other milk", productType: "milk"))
        batch.offers.append(CatalogOffer(id: "alternative-offer", productID: "alternative", storeID: "s1",
                                        price: 110, currency: "RUB"))
        try await repository.importCatalog(batch)
        let initial = expectation(description: "Initial alternatives")
        let updated = expectation(description: "Alternative price updates")
        let removed = expectation(description: "Alternative leaves the group")
        let observation = repository.observeRelatedProducts(to: "p1", storeID: nil).sink { items in
            XCTAssertTrue(Thread.isMainThread)
            if items.isEmpty { removed.fulfill() }
            else if items.first?.offers.first?.offer.price == 120 { updated.fulfill() }
            else { initial.fulfill() }
        }
        defer { observation.cancel() }
        await fulfillment(of: [initial], timeout: 5)
        batch.offers[1].price = 120
        try await repository.importCatalog(CatalogImport(offers: [batch.offers[1]]))
        await fulfillment(of: [updated], timeout: 5)
        batch.products[1].productType = "bread"
        try await repository.importCatalog(CatalogImport(products: [batch.products[1]]))
        await fulfillment(of: [removed], timeout: 5)
    }

    func testRelatedQueryBoundsItsOwnResultsAndHandlesMissingGroups() throws {
        let products = [CatalogProduct(id: "selected", name: "Selected", category: "Dairy")]
            + (0...CatalogSearch.resultLimit).map { CatalogProduct(id: "p\($0)", name: "Product \($0)", category: "Dairy") }
            + [CatalogProduct(id: "ungrouped", name: "Ungrouped")]
        let snapshot = try CatalogFixtures.snapshot(CatalogImport(products: products))
        let related = snapshot.relatedItems(to: "selected")
        XCTAssertEqual(related.count, CatalogSearch.resultLimit)
        XCTAssertFalse(related.contains { $0.id == "selected" })
        XCTAssertTrue(snapshot.relatedItems(to: "ungrouped").isEmpty)
        XCTAssertTrue(snapshot.relatedItems(to: "missing").isEmpty)
    }

    func testRelatedQueryFiltersTheStoreBeforeApplyingItsLimit() throws {
        var batch = CatalogImport(products: (0..<CatalogSearch.resultLimit).map {
            CatalogProduct(id: "unavailable-\($0)", name: "A product \($0)", productType: "milk")
        }, stores: [CatalogStore(id: "s1", name: "Store")])
        batch.products += [
            CatalogProduct(id: "selected", name: "Selected", productType: "milk"),
            CatalogProduct(id: "available", name: "Z available", productType: "milk")
        ]
        batch.offers = [CatalogOffer(id: "offer", productID: "available", storeID: "s1", price: 100, currency: "RUB", inStock: true)]
        let snapshot = try CatalogFixtures.snapshot(batch)
        XCTAssertEqual(snapshot.relatedItems(to: "selected", storeID: "s1").map(\.id), ["available"])
        XCTAssertTrue(snapshot.relatedItems(to: "selected", storeID: "missing").isEmpty)
    }

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

private actor ConditionalCatalogSource: CatalogSource {
    private(set) var headers: [String?] = []
    func loadCatalog(ifNoneMatch: String?) async throws -> CatalogSourceResult {
        headers.append(ifNoneMatch)
        try await Task.sleep(for: .milliseconds(30))
        return .notModified
    }
}

private actor LateFailureCatalogSource: CatalogSource {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false
    func loadCatalog(ifNoneMatch: String?) async throws -> CatalogSourceResult {
        if !hasStarted {
            await withCheckedContinuation { continuation = $0; hasStarted = true }
            throw URLError(.notConnectedToInternet)
        }
        return .snapshot(CatalogFixtures.export())
    }
    func releaseFailure() { continuation?.resume(); continuation = nil }
}
