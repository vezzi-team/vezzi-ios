import CoreData
import XCTest
@testable import vezzi_ios

@MainActor
final class CoreDataCatalogCacheTests: XCTestCase {
    func testVersionedSnapshotReplacementIsAtomicAndSurvivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Snapshot.sqlite")
        let persistence = PersistenceController(storeURL: url)
        let cache = CoreDataCatalogCache(persistence: persistence)
        var first = CatalogFixtures.catalog()
        first.products.append(CatalogProduct(id: "removed", name: "Removed"))
        try await cache.save(CatalogFixtures.export(first))
        var second = CatalogFixtures.catalog(price: Decimal(string: "89.99")!, date: Date(timeIntervalSince1970: 50))
        second.offers[0].cardPrice = Decimal(string: "79.99")!
        second.offers[0].priceConditions = "With card"
        second.stores[0].format = "supermarket"
        let replacement = CatalogFixtures.export(second, version: 2)
        try await cache.save(replacement)
        var invalid = replacement
        invalid.offers[0] = StoredCatalogOffer(offer: CatalogOffer(id: "bad", productID: "missing", storeID: "s1", price: 1, currency: "RUB"), cachedAt: Date())
        do { try await cache.save(invalid); XCTFail("Expected rollback") } catch { }
        try closeStore(persistence)
        let reopened = PersistenceController(storeURL: url)
        let snapshot = try await CoreDataCatalogCache(persistence: reopened).loadSnapshot()
        XCTAssertEqual(snapshot.metadata, replacement.metadata)
        XCTAssertEqual(snapshot.products.count, 1)
        XCTAssertNil(snapshot.products["removed"])
        XCTAssertEqual(snapshot.offers["o1"]?.offer.price, Decimal(string: "89.99"))
        XCTAssertEqual(snapshot.offers["o1"]?.offer.cardPrice, Decimal(string: "79.99"))
        XCTAssertEqual(snapshot.offers["o1"]?.offer.priceConditions, "With card")
        XCTAssertEqual(snapshot.stores["s1"]?.format, "supermarket")
        try closeStore(reopened)
    }

    func testSQLitePreservesExactDecimalsAndMetadataAfterReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Catalog.sqlite")
        let price = Decimal(string: "123456.789123456789")!
        let quantity = Decimal(string: "0.123456789123456789")!
        var batch = CatalogFixtures.catalog(price: price)
        batch.products[0].packageQuantity = quantity
        batch.offers[0].sourceID = "source"
        batch.offers[0].sourceProductID = "source-product"
        batch.offers[0].sourceURL = URL(string: "https://example.com/product")
        batch.offers[0].dataOrigin = "feed"
        batch.offers[0].priceType = "regular"
        let original = PersistenceController(storeURL: url)
        try await CoreDataCatalogCache(persistence: original).save(CatalogFixtures.cached(batch))
        try closeStore(original)
        let reopened = PersistenceController(storeURL: url)
        let stored = try await CoreDataCatalogCache(persistence: reopened).loadSnapshot()
        XCTAssertEqual(stored.products["p1"], batch.products.first)
        XCTAssertEqual(stored.offers["o1"]?.offer, batch.offers.first)
        XCTAssertEqual(stored.offers["o1"]?.cachedAt, CatalogFixtures.cachedAt)
        XCTAssertEqual(stored.items(matching: "").first?.offers.first?.store.id, "s1")
        try closeStore(reopened)
    }

    func testDecimalEncodingCoversSmallAndLargeValues() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(storeURL: directory.appendingPathComponent("Decimals.sqlite"))
        let cache = CoreDataCatalogCache(persistence: persistence)
        let amounts = ["0", "0.00000000000000000000000000000000000001", "99999999999999999999999999999999999999", "99.90"]
        var batch = CatalogFixtures.catalog()
        batch.offers = amounts.enumerated().map { index, text in
            CatalogOffer(id: "o\(index)", productID: "p1", storeID: "s1", price: Decimal(string: text)!, currency: "RUB")
        }
        try await cache.save(CatalogFixtures.cached(batch))
        let stored = try await cache.loadSnapshot()
        for offer in batch.offers { XCTAssertEqual(stored.offers[offer.id]?.offer.price, offer.price) }
        try closeStore(persistence)
    }

    func testSQLiteSnapshotReadKeepsOneGenerationAcrossConcurrentWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = PersistenceController(storeURL: directory.appendingPathComponent("Concurrent.sqlite"))
        defer { try? closeStore(persistence) }
        let cache = CoreDataCatalogCache(persistence: persistence)
        try await cache.save(CatalogFixtures.cached())

        let productsRead = expectation(description: "First fetch completed")
        let continueReading = DispatchSemaphore(value: 0)
        async let reading = persistence.performSnapshotRead { context in
            let productIDs = try context.fetch(NSFetchRequest<ProductEntity>(entityName: "ProductEntity")).map(\.id)
            productsRead.fulfill()
            // Force a commit between fetches without relying on scheduler timing.
            XCTAssertEqual(continueReading.wait(timeout: .now() + 5), .success)
            let storeNames = try context.fetch(NSFetchRequest<StoreEntity>(entityName: "StoreEntity")).map(\.name)
            let offerIDs = try context.fetch(NSFetchRequest<OfferEntity>(entityName: "OfferEntity")).map(\.id)
            return (productIDs, storeNames, offerIDs)
        }
        defer { continueReading.signal() }
        await fulfillment(of: [productsRead], timeout: 5)

        let addition = CatalogImport(
            products: [CatalogProduct(id: "p2", name: "Bread")],
            stores: [CatalogStore(id: "s1", name: "Renamed store"), CatalogStore(id: "s2", name: "New store")],
            offers: [CatalogOffer(id: "o2", productID: "p2", storeID: "s2", price: 70, currency: "RUB")]
        )
        try await cache.save(CatalogFixtures.cached(addition))
        continueReading.signal()

        let (productIDs, storeNames, offerIDs) = try await reading
        XCTAssertEqual(productIDs, ["p1"])
        XCTAssertEqual(storeNames, ["Store"])
        XCTAssertEqual(offerIDs, ["o1"])

        // A new snapshot must advance to the completed write, not remain pinned.
        let latest = try await cache.loadSnapshot()
        XCTAssertEqual(Set(latest.products.keys), ["p1", "p2"])
        XCTAssertEqual(latest.stores["s1"]?.name, "Renamed store")
        XCTAssertEqual(latest.stores["s2"]?.name, "New store")
        XCTAssertEqual(Set(latest.offers.keys), ["o1", "o2"])
    }

    func testVersionOneStoreMigratesWithoutLosingValuesOrLinks() async throws {
        try await assertLegacyMigration(from: "Polka")
    }

    func testVersionTwoStoreMigratesWithExactDecimals() async throws {
        try await assertLegacyMigration(from: "PolkaV2")
    }

    private func assertLegacyMigration(from version: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Legacy.sqlite")
        let modelURL = try XCTUnwrap(Bundle.main.url(forResource: "Polka", withExtension: "momd"))
            .appendingPathComponent("\(version).mom")
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        // Use generic objects to seed the historical schema, independently of current subclasses.
        for entity in oldModel.entities { entity.managedObjectClassName = "NSManagedObject" }
        let old = NSPersistentContainer(name: "Legacy", managedObjectModel: oldModel)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            old.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await old.performBackgroundTask { context in
            let product = NSEntityDescription.insertNewObject(forEntityName: "ProductEntity", into: context)
            product.setValue("p1", forKey: "id")
            product.setValue("Молоко", forKey: "name")
            product.setValue(NSDecimalNumber(string: "900"), forKey: "packageQuantity")
            product.setValue("мл", forKey: "packageUnit")
            let store = NSEntityDescription.insertNewObject(forEntityName: "StoreEntity", into: context)
            store.setValue("s1", forKey: "id")
            store.setValue("Legacy store", forKey: "name")
            store.setValue(true, forKey: "isActive")
            let offer = NSEntityDescription.insertNewObject(forEntityName: "OfferEntity", into: context)
            offer.setValue("o1", forKey: "id")
            offer.setValue(product, forKey: "product")
            offer.setValue(store, forKey: "store")
            offer.setValue(NSDecimalNumber(string: "99.90"), forKey: "price")
            if version == "PolkaV2" {
                offer.setValue("99.900000000000000001", forKey: "priceText")
                product.setValue("900", forKey: "packageQuantityText")
            }
            offer.setValue("RUB", forKey: "currency")
            offer.setValue(CatalogFixtures.cachedAt, forKey: "cachedAt")
            offer.setValue(Date(timeIntervalSince1970: 100), forKey: "sourceUpdatedAt")
            offer.setValue("legacy-source", forKey: "sourceID")
            try context.save()
        }
        for store in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(store) }
        let persistence = PersistenceController(storeURL: url)
        let cache = CoreDataCatalogCache(persistence: persistence)
        let migrated = try await cache.loadSnapshot()
        XCTAssertEqual(migrated.products["p1"]?.packageQuantity, 900)
        XCTAssertEqual(migrated.offers["o1"]?.offer.price, Decimal(string: version == "PolkaV2" ? "99.900000000000000001" : "99.90"))
        XCTAssertNil(migrated.metadata)
        XCTAssertEqual(migrated.offers["o1"]?.cachedAt, CatalogFixtures.cachedAt)
        XCTAssertEqual(migrated.offers["o1"]?.offer.sourceID, "legacy-source")
        XCTAssertEqual(migrated.items(matching: "").first?.offers.first?.store.name, "Legacy store")
        let exact = Decimal(string: "123456.789123456789")!
        try await cache.save(CatalogFixtures.cached(CatalogFixtures.catalog(price: exact)))
        try closeStore(persistence)
        let reopened = PersistenceController(storeURL: url)
        let updated = try await CoreDataCatalogCache(persistence: reopened).loadSnapshot()
        XCTAssertEqual(updated.offers["o1"]?.offer.price, exact)
        try closeStore(reopened)
    }

    func testInvalidReferenceRollsBackWholeCacheWrite() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = CoreDataCatalogCache(persistence: persistence)
        try await cache.save(CatalogFixtures.cached())
        let invalid = CatalogImport(products: [CatalogProduct(id: "p2", name: "Must roll back")], offers: [
            CatalogOffer(id: "bad", productID: "p2", storeID: "missing", price: 100, currency: "RUB")
        ])
        do {
            try await cache.save(CatalogFixtures.cached(invalid))
            XCTFail("Invalid references must reject the whole write")
        } catch { XCTAssertEqual(error as? CatalogError, .missingReference(offerID: "bad")) }
        let stored = try await cache.loadSnapshot()
        XCTAssertEqual(Set(stored.products.keys), ["p1"])
        XCTAssertEqual(Set(stored.offers.keys), ["o1"])
    }

    func testDuplicateIDsAndInvalidValuesAreRejected() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = CoreDataCatalogCache(persistence: persistence)
        let product = CatalogProduct(id: "duplicate", name: "Product")
        let invalidBatches = [
            CatalogImport(products: [product, product]),
            CatalogFixtures.catalog(price: -1),
            CatalogImport(stores: [CatalogStore(id: "s", name: "Store", latitude: 91, longitude: 0)]),
            CatalogImport(products: [CatalogProduct(id: "p", name: "Product", packageQuantity: 1)])
        ]
        for batch in invalidBatches {
            do { try await cache.save(CatalogFixtures.cached(batch)); XCTFail("Invalid data must be rejected") }
            catch { XCTAssertTrue(error is CatalogError) }
        }
        let stored = try await cache.loadSnapshot()
        XCTAssertTrue(stored.products.isEmpty)
        XCTAssertTrue(stored.stores.isEmpty)
    }

    func testOlderAndUndatedOffersKeepPriceAndCacheMetadata() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = CoreDataCatalogCache(persistence: persistence)
        try await cache.save(CatalogFixtures.cached(CatalogFixtures.catalog(price: 120, date: Date(timeIntervalSince1970: 200))))
        try await cache.save(CatalogFixtures.cached(CatalogFixtures.catalog(price: 90), at: Date()))
        try await cache.save(CatalogFixtures.cached(CatalogFixtures.catalog(price: 80, date: nil), at: Date()))
        let stored = try await cache.loadSnapshot()
        XCTAssertEqual(stored.offers["o1"]?.offer.price, 120)
        XCTAssertEqual(stored.offers["o1"]?.cachedAt, CatalogFixtures.cachedAt)
    }

    func testConcurrentCacheWritesDoNotCreateDuplicateIDs() async throws {
        let cache = CoreDataCatalogCache(persistence: PersistenceController(inMemory: true))
        let batch = CatalogFixtures.cached()
        async let first: Void = cache.save(batch)
        async let second: Void = cache.save(batch)
        _ = try await (first, second)
        let stored = try await cache.loadSnapshot()
        XCTAssertEqual(stored.products.count, 1)
        XCTAssertEqual(stored.stores.count, 1)
        XCTAssertEqual(stored.offers.count, 1)
    }

    func testMalformedExactValueIsReportedInsteadOfFallingBackToRoundedPrice() async throws {
        let persistence = PersistenceController(inMemory: true)
        let cache = CoreDataCatalogCache(persistence: persistence)
        try await cache.save(CatalogFixtures.cached())
        try await persistence.container.performBackgroundTask { context in
            let offer = try XCTUnwrap(context.fetch(NSFetchRequest<OfferEntity>(entityName: "OfferEntity")).first)
            offer.priceText = "123invalid"
            try context.save()
        }
        do { _ = try await cache.loadSnapshot(); XCTFail("Invalid cache contents must be surfaced") }
        catch { XCTAssertEqual(error as? CatalogError, .invalidRecord(entity: "Offer", id: "o1")) }
    }

    func testOpeningFailureDoesNotDeleteOrReplaceExistingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Broken.sqlite")
        let original = Data("This is not a SQLite store".utf8)
        try original.write(to: url)
        let persistence = PersistenceController(storeURL: url)
        for _ in 0..<2 {
            do { try await persistence.load(); XCTFail("A broken store must report an error") } catch {}
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
}
