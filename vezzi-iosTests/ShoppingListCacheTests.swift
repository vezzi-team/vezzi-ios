import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingListCacheTests: XCTestCase {
    func testDiskRoundTripDistinguishesConfirmedAbsenceFromUnresolvedCart() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let account = ShoppingListTestAccount.make("account")
        let cache = FileShoppingListCache(directory: folder)
        for hasResolvedCart in [false, true] {
            let snapshot = ShoppingListCacheSnapshot(cart: nil, pending: [:], plan: nil, hasResolvedCart: hasResolvedCart)
            try await cache.save(snapshot, account: account)
            let loaded = try await FileShoppingListCache(directory: folder).load(account: account)
            XCTAssertNotNil(loaded)
            XCTAssertNil(loaded?.cart)
            XCTAssertEqual(loaded?.hasResolvedCart, hasResolvedCart)
        }
    }

    func testLegacySnapshotsOnlyConfirmAnExistingCart() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let account = ShoppingListTestAccount.make("account")
        let cache = FileShoppingListCache(directory: folder)
        for snapshot in [sampleSnapshot(), ShoppingListCacheSnapshot(cart: nil, pending: [:], plan: nil, hasResolvedCart: true)] {
            try await cache.save(snapshot, account: account)
            let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
            let data = try Data(contentsOf: file)
            var envelope = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            var legacy = try XCTUnwrap(envelope["snapshot"] as? [String: Any])
            legacy.removeValue(forKey: "hasResolvedCart")
            envelope["snapshot"] = legacy
            try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0).write(to: file)

            let loaded = try await cache.load(account: account)
            XCTAssertEqual(loaded?.hasResolvedCart, snapshot.cart != nil)
            XCTAssertEqual(loaded?.cart?.id, snapshot.cart?.id)
            XCTAssertEqual(loaded?.plan?.cartID, snapshot.plan?.cartID)
        }
    }

    func testDiskRoundTripKeepsExactPricesProductsAndCalculatedRoute() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let snapshot = sampleSnapshot()
        try await cache.save(snapshot, account: ShoppingListTestAccount.make("account"))
        let loadedValue = try await FileShoppingListCache(directory: folder).load(account: ShoppingListTestAccount.make("account"))
        let loaded = try XCTUnwrap(loadedValue)
        XCTAssertEqual(loaded.cart?.id, snapshot.cart?.id)
        XCTAssertEqual(loaded.cart?.quantities, ["product": 2])
        XCTAssertEqual(loaded.cart?.items.first?.product, snapshot.cart?.items.first?.product)
        let plan = try XCTUnwrap(loaded.plan?.result.plans.first)
        let expected = try XCTUnwrap(snapshot.plan?.result.plans.first)
        XCTAssertEqual(plan.total, expected.total)
        XCTAssertEqual(plan.stops.first?.items.first?.unitPrice, expected.stops.first?.items.first?.unitPrice)
        XCTAssertEqual(plan.stops.first?.items.first?.cardPrice, expected.stops.first?.items.first?.cardPrice)
        XCTAssertEqual(plan.points, expected.points)
        XCTAssertEqual(plan.stops.first?.store, expected.stops.first?.store)
        XCTAssertEqual(loaded.plan?.calculatedAt, snapshot.plan?.calculatedAt)
    }

    func testAccountsAreIsolatedAndRemovalIsIdempotent() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let first = ShoppingListCacheSnapshot(cart: nil, pending: [.active: ["first": 1]], plan: nil)
        let second = ShoppingListCacheSnapshot(cart: nil, pending: [.active: ["second": 2]], plan: nil)
        try await cache.save(first, account: ShoppingListTestAccount.make("../first"))
        try await cache.save(second, account: ShoppingListTestAccount.make("second"))
        let firstLoaded = try await cache.load(account: ShoppingListTestAccount.make("../first"))
        let secondLoaded = try await cache.load(account: ShoppingListTestAccount.make("second"))
        XCTAssertEqual(firstLoaded?.pending, first.pending)
        XCTAssertEqual(secondLoaded?.pending, second.pending)
        try await cache.remove(account: ShoppingListTestAccount.make("../first"))
        try await cache.remove(account: ShoppingListTestAccount.make("../first"))
        let removed = try await cache.load(account: ShoppingListTestAccount.make("../first"))
        let remaining = try await cache.load(account: ShoppingListTestAccount.make("second"))
        XCTAssertNil(removed)
        XCTAssertEqual(remaining?.pending, second.pending)
    }

    func testMissingSnapshotIsNotAnErrorAndHasNoCalculation() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let missing = try await cache.load(account: ShoppingListTestAccount.make("account"))
        XCTAssertNil(missing)
        var snapshot = sampleSnapshot()
        snapshot.plan = nil
        try await cache.save(snapshot, account: ShoppingListTestAccount.make("account"))
        let loaded = try await cache.load(account: ShoppingListTestAccount.make("account"))
        XCTAssertNotNil(loaded?.cart)
        XCTAssertNil(loaded?.plan)
    }

    func testCorruptionAndUnsupportedVersionsAreReported() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        try await cache.save(sampleSnapshot(), account: ShoppingListTestAccount.make("account"))
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let original = try Data(contentsOf: file)
        try Data("broken cache".utf8).write(to: file)
        do {
            _ = try await cache.load(account: ShoppingListTestAccount.make("account"))
            XCTFail("Corruption must not masquerade as an empty cart")
        } catch { }
        var envelope = try XCTUnwrap(PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any])
        envelope["version"] = 999
        try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0).write(to: file)
        do {
            _ = try await cache.load(account: ShoppingListTestAccount.make("account"))
            XCTFail("An unsupported schema must not be restored")
        } catch ShoppingListCacheError.invalidSnapshot { }
    }

    func testNewSessionCannotRestoreOldEditsAndOldCleanupCannotDeleteNewData() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let old = ShoppingListTestAccount.make("account")
        let new = ShoppingListTestAccount.make("account", sessionID: UUID())
        let snapshot = sampleSnapshot()
        try await cache.save(snapshot, account: old)
        let restarted = FileShoppingListCache(directory: folder)
        let excluded = try await restarted.load(account: new)
        XCTAssertNil(excluded)
        try await restarted.save(snapshot, account: new)
        try await cache.remove(account: old)
        let retained = try await restarted.load(account: new)
        XCTAssertEqual(retained?.cart?.id, snapshot.cart?.id)
    }

    func testUnscopedVersionOneSnapshotIsNotRestored() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let account = ShoppingListTestAccount.make("account")
        try await cache.save(sampleSnapshot(), account: account)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let hash = file.lastPathComponent.components(separatedBy: ".")[0]
        let legacy = folder.appendingPathComponent(hash).appendingPathExtension("plist")
        try FileManager.default.moveItem(at: file, to: legacy)
        let loaded = try await cache.load(account: account)
        XCTAssertNil(loaded)
        try await cache.remove(account: account)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testDelayedOldSessionWriteCannotOverwriteNewSessionData() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let old = ShoppingListTestAccount.make("account")
        let new = ShoppingListTestAccount.make("account", sessionID: UUID())
        let fresh = ShoppingListCacheSnapshot(cart: nil, pending: [.active: ["new": 2]], plan: nil)
        try await cache.save(fresh, account: new)
        try await cache.save(sampleSnapshot(), account: old)
        let loaded = try await cache.load(account: new)
        XCTAssertEqual(loaded?.pending, fresh.pending)
    }

    func testMismatchedCalculationCannotReplaceValidSnapshot() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let valid = sampleSnapshot()
        try await cache.save(valid, account: ShoppingListTestAccount.make("account"))
        var invalid = valid
        invalid.pending = [.cart(try XCTUnwrap(invalid.cart).id): ["product": 3]]
        do {
            try await cache.save(invalid, account: ShoppingListTestAccount.make("account"))
            XCTFail("A calculation must not accompany unacknowledged changes")
        } catch ShoppingListCacheError.invalidSnapshot { }
        let loaded = try await cache.load(account: ShoppingListTestAccount.make("account"))
        XCTAssertEqual(loaded?.plan?.cartID, valid.cart?.id)
        XCTAssertTrue(loaded?.pending.isEmpty == true)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func sampleSnapshot() -> ShoppingListCacheSnapshot {
        let price = Decimal(string: "90071992547409.93")!
        let product = CatalogProduct(id: "product", name: "Product", brand: "Brand",
                                     packageQuantity: Decimal(string: "0.1234567890123456789")!, packageUnit: "kg")
        let cart = ShoppingCart(id: UUID(), name: "List", status: "active", items: [.init(product: product, quantity: 2)])
        let item = ShoppingPlanItem(product: product, quantity: 2, unitPrice: price,
                                    cardPrice: Decimal(string: "123.45")!, priceConditions: "With a card")
        let store = CatalogStore(id: "store", name: "Store", chainName: "Chain", address: "Street", latitude: 60, longitude: 30)
        let stop = ShoppingPlanStop(position: 1, store: store, items: [item], subtotal: price * 2)
        let plan = ShoppingPlan(id: UUID(), total: price * 2, savings: Decimal(string: "0.01")!, totalSeconds: 780,
                                walkingMeters: 800, stops: [stop], points: [.previewOrigin, .init(latitude: 60, longitude: 30)],
                                usesRoadNetwork: true, isSynthetic: false)
        let result = ShoppingPlanResult(plans: [plan], baselinePrice: price * 2 + 1, problem: nil, isSynthetic: false)
        return ShoppingListCacheSnapshot(cart: cart, pending: [:],
                                         plan: CachedShoppingPlan(cartID: cart.id, quantities: cart.quantities, origin: .previewOrigin,
                                                                  calculatedAt: Date(timeIntervalSince1970: 1_700_000_000), result: result))
    }
}
