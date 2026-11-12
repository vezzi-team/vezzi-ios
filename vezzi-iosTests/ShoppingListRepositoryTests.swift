import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingListRepositoryTests: XCTestCase {
    func testEmptyListAndOfflineFeedbackPreserveGuestEdits() async {
        let service = ControlledShoppingService()
        await service.setOffline(true)
        let repository = ShoppingListRepository(service: service)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        XCTAssertEqual(model.contentState, .empty)
        XCTAssertNil(model.message, "An untouched guest list needs no warning")
        repository.setAccount(ShoppingListTestAccount.make("account"))
        XCTAssertEqual(model.contentState, .loading)
        await repository.refresh()
        XCTAssertEqual(model.contentState, .offline)

        repository.selection.setQuantity(1, for: "1")
        XCTAssertEqual(model.contentState, .products, "A local item stays usable without a server cart")
        await repository.refresh()
        XCTAssertEqual(model.contentState, .products)
        repository.setAccount(nil)
        XCTAssertEqual(model.contentState, .empty, "Offline account feedback must not leak into guest mode")
    }

    func testSavedEmptyCartShowsEmptyListWhenOffline() async {
        let service = ControlledShoppingService()
        let cache = MemoryShoppingListCache()
        let first = ShoppingListRepository(service: service, cache: cache)
        first.setAccount(ShoppingListTestAccount.make("account"))
        await first.refresh()
        await service.setOffline(true)

        let restored = ShoppingListRepository(service: service, cache: cache)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertNotNil(restored.cart)
        XCTAssertTrue(restored.selection.quantities.isEmpty)
        XCTAssertEqual(restored.failure, .offline)
        XCTAssertEqual(model.contentState, .empty)
    }

    func testEmptyAccountCreatesCartOnlyOnFirstEditAndRecoversLostCreateResponse() async {
        let service = ControlledShoppingService()
        await service.startWithoutCart()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        let initialCreates = await service.creates
        XCTAssertEqual(initialCreates, 0)
        await service.failAfterNextCreate()
        repository.selection.setQuantity(2, for: "1")
        await repository.refresh()
        XCTAssertEqual(repository.failure, .offline)
        await repository.refresh()
        XCTAssertNil(repository.failure)
        XCTAssertEqual(repository.selection.quantities, ["1": 2])
        let creates = await service.creates
        XCTAssertEqual(creates, 1, "Reload active carts before retrying a lost create response")
    }

    func testConfirmedAbsenceOfCartRemainsEmptyOfflineAndAfterRestart() async {
        let service = ControlledShoppingService()
        await service.startWithoutCart()
        let cache = MemoryShoppingListCache()
        let original = ShoppingListRepository(service: service, cache: cache)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: original)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        XCTAssertNil(original.cart)
        XCTAssertTrue(original.hasResolvedCart)
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.hasResolvedCart, true)

        await service.setOffline(true)
        await original.refresh()
        XCTAssertEqual(original.failure, .offline)
        XCTAssertEqual(model.contentState, .empty)
        XCTAssertNil(model.message)

        let restored = ShoppingListRepository(service: service, cache: cache)
        let restoredModel = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertNil(restored.cart)
        XCTAssertEqual(restored.failure, .offline)
        XCTAssertEqual(restoredModel.contentState, .empty)

        restored.setAccount(ShoppingListTestAccount.make("other"))
        XCTAssertFalse(restored.hasResolvedCart, "Confirmed absence belongs only to its account/session")
        await restored.refresh()
        XCTAssertEqual(restoredModel.contentState, .offline)
    }

    func testFailedFirstLookupDoesNotCacheAConfirmedEmptyList() async {
        let service = ControlledShoppingService()
        await service.setOffline(true)
        let cache = MemoryShoppingListCache()
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.hasResolvedCart, false)

        let restored = ShoppingListRepository(service: service, cache: cache)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertFalse(restored.hasResolvedCart)
        XCTAssertEqual(model.contentState, .offline)
    }

    func testDeletingLastItemRetainsCacheFailureUntilStorageRecovers() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let repository = ShoppingListRepository(service: service, cache: cache)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.setOffline(true)
        await cache.setFailing(true)
        repository.selection.setQuantity(0, for: "1")
        await repository.refresh()
        XCTAssertEqual(model.contentState, .empty)
        XCTAssertEqual(model.message, Texts.ShoppingList.cacheError)
        let oldSnapshot = await cache.snapshot("account")
        XCTAssertEqual(oldSnapshot?.cart?.quantities, ["1": 1], "The deletion has not reached disk or server")

        await cache.setFailing(false)
        await repository.refresh()
        XCTAssertEqual(model.contentState, .empty)
        XCTAssertNil(model.message, "Successful local persistence clears the warning even while offline")
    }

    func testDeletingLastItemRetainsServerRejectionFeedback() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        let cart = try XCTUnwrap(repository.cart)
        await service.rejectWrites(in: cart.id, with: APIError.http(status: 500, code: nil, requestID: nil, retryAfter: nil))
        repository.selection.setQuantity(0, for: "1")
        await repository.refresh()
        XCTAssertEqual(model.contentState, .empty)
        XCTAssertEqual(model.message, Texts.ShoppingList.loadError)
    }

    func testRestoreMergesGuestEditsWithoutClearingServerProductsOrHaptics() async {
        let service = ControlledShoppingService(quantities: ["1": 2])
        let selection = ProductSelection()
        selection.setQuantity(3, for: "2")
        let feedback = selection.feedbackRevision
        let repository = ShoppingListRepository(service: service, selection: selection)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        XCTAssertEqual(selection.quantities, ["1": 2, "2": 3])
        XCTAssertEqual(selection.feedbackRevision, feedback)
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "2", quantity: 3, exists: false)])
        XCTAssertNil(repository.failure)
    }

    func testRapidEditsCoalesceAndDeleteUsesTheSameSelection() async {
        let service = ControlledShoppingService()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        for quantity in 1...5 { repository.selection.setQuantity(quantity, for: "1") }
        await repository.refresh()
        var writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "1", quantity: 5, exists: false)])
        repository.selection.setQuantity(0, for: "1")
        await repository.refresh()
        writes = await service.writes
        XCTAssertEqual(writes.last, .init(id: "1", quantity: 0, exists: true))
        XCTAssertTrue(repository.selection.quantities.isEmpty)
    }

    func testNewerEditSurvivesAnInFlightWrite() async {
        let service = ControlledShoppingService()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.pauseNextWrite()
        repository.selection.setQuantity(1, for: "1")
        await service.waitUntilPaused()
        repository.selection.setQuantity(4, for: "1")
        await service.resume()
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantity(for: "1"), 4)
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "1", quantity: 1, exists: false), .init(id: "1", quantity: 4, exists: true)])
    }

    func testAmbiguousAddReloadsBeforeRetryAndDoesNotDoubleQuantity() async {
        let service = ControlledShoppingService()
        await service.failAfterNextWrite()
        let repository = ShoppingListRepository(service: service)
        repository.selection.setQuantity(3, for: "1")
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        XCTAssertEqual(repository.failure, .offline)
        XCTAssertEqual(repository.selection.quantity(for: "1"), 3)
        await repository.refresh()
        XCTAssertNil(repository.failure)
        XCTAssertEqual(repository.selection.quantity(for: "1"), 3)
        let writes = await service.writes
        XCTAssertEqual(writes.count, 1, "A successful POST with a lost response must not be replayed")
    }

    func testLogoutRejectsLateWriteAndClearsPersonalState() async {
        let service = ControlledShoppingService()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.pauseNextWrite()
        repository.selection.setQuantity(2, for: "1")
        await service.waitUntilPaused()
        repository.setAccount(nil)
        await service.resume()
        await Task.yield()
        XCTAssertNil(repository.cart)
        XCTAssertNil(repository.planResult)
        XCTAssertNil(repository.accountID)
        XCTAssertFalse(repository.isBusy)
        XCTAssertTrue(repository.selection.quantities.isEmpty)
    }

    func testAccountSwitchRejectsPreviousAccountsReply() async {
        let service = ControlledShoppingService()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("first"))
        await repository.refresh()
        await service.pauseNextWrite()
        repository.selection.setQuantity(2, for: "1")
        await service.waitUntilPaused()
        await service.replaceCart(quantities: ["2": 7])
        repository.setAccount(ShoppingListTestAccount.make("second"))
        await repository.refresh()
        await service.resume()
        await Task.yield()
        XCTAssertEqual(repository.selection.quantities, ["2": 7])
        XCTAssertEqual(repository.accountID, "second")
    }

    func testPlansWaitForWritesAndObsoleteCalculationCannotReplaceNewerCart() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.pauseNextPlan()
        repository.setPresented(true)
        await service.waitUntilPaused()
        repository.selection.setQuantity(3, for: "1")
        XCTAssertNil(repository.planResult)
        await service.resume()
        await repository.refresh()
        XCTAssertEqual(repository.planResult?.plans.first?.total, 300)
        let maxConcurrent = await service.maximumActivePlans
        XCTAssertEqual(maxConcurrent, 1)
    }

    func testNoPlansRetainsCartAndExplainsFailure() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        await service.returnNoPlans()
        let repository = ShoppingListRepository(service: service)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantities, ["1": 1])
        XCTAssertEqual(repository.planResult?.problem, "items_unavailable")
        XCTAssertEqual(model.message, Texts.ShoppingList.itemsUnavailable)
        XCTAssertNil(model.plan)
        XCTAssertNil(model.comparisonPrice)
        XCTAssertNil(model.priceSavings)
        XCTAssertEqual(model.products.first?.name, "Product 1", "Cart records remain usable without a catalog cache")
    }

    func testModeSwitchComparesServerOptionsInsteadOfBaselineWithoutAnotherRequest() async {
        let service = ControlledShoppingService(quantities: ["1": 2], baselinePrice: 300)
        let repository = ShoppingListRepository(service: service)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        XCTAssertEqual(repository.planResult?.baselinePrice, 300)
        XCTAssertEqual(model.plan?.total, 200)
        XCTAssertEqual(model.comparisonPrice, 220)
        XCTAssertEqual(model.plan?.savings, 0)
        XCTAssertEqual(model.priceSavings, 20, "Compare the displayed plans, independently of server savings and the baseline")
        XCTAssertEqual(model.products.first?.lowestPrice, 100)
        model.mode = .faster
        XCTAssertEqual(model.plan?.total, 220)
        XCTAssertEqual(model.comparisonPrice, 200)
        XCTAssertEqual(model.priceSavings, 20)
        XCTAssertEqual(model.products.first?.lowestPrice, 110)
        XCTAssertEqual(model.savedMinutes, 5)
        let count = await service.planRequests
        XCTAssertEqual(count, 1)
    }

    func testPriceSavingsHandleEqualAndFractionalTotals() async {
        let cases: [(Decimal, Decimal)] = [(100, 0), (Decimal(10001) / 100, Decimal(2) / 100)]
        for (unitPrice, expectedSavings) in cases {
            let service = ControlledShoppingService(quantities: ["1": 2], fastUnitPrice: unitPrice)
            let repository = ShoppingListRepository(service: service)
            let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
            repository.setAccount(ShoppingListTestAccount.make("account"))
            repository.setPresented(true)
            await repository.refresh()

            XCTAssertEqual(model.priceSavings, expectedSavings)
        }
    }

    func testLogoutClearsPresentedRouteSynchronously() async throws {
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 2]))
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("first"))
        repository.setPresented(true)
        await repository.refresh()
        model.routePlan = try XCTUnwrap(model.plan)
        model.showProduct(try XCTUnwrap(model.products.first))
        XCTAssertNotNil(model.selectedProductOffer)

        repository.setAccount(nil)

        XCTAssertNil(model.routePlan)
        XCTAssertNil(repository.planResult)
        XCTAssertNil(model.selectedProduct)
        XCTAssertNil(model.selectedProductOffer)
    }

    func testAccountSwitchClearsPresentedRouteBeforeLoadingTheNewAccount() async throws {
        let service = ControlledShoppingService(quantities: ["1": 2])
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("first"))
        repository.setPresented(true)
        await repository.refresh()
        // The view model may be created after the account has already been restored.
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        model.routePlan = try XCTUnwrap(model.plan)
        model.showProduct(try XCTUnwrap(model.products.first))

        await service.replaceCart(quantities: ["2": 1])
        repository.setAccount(ShoppingListTestAccount.make("second"))

        XCTAssertNil(model.routePlan)
        XCTAssertNil(model.selectedProduct)
        XCTAssertNil(model.selectedProductOffer)
        await repository.refresh()
        XCTAssertNil(model.routePlan, "New plans must not reopen the previous account's sheet")
        XCTAssertEqual(model.products.map(\.id), ["2"])
    }

    func testSameAccountAndRecalculationPreserveThePresentedRouteSnapshot() async throws {
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 2]))
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        let presented = try XCTUnwrap(model.plan)
        model.routePlan = presented

        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.selection.setQuantity(3, for: "1")
        await repository.refresh()

        XCTAssertEqual(model.plan?.total, 300)
        XCTAssertEqual(model.routePlan?.id, presented.id)
        XCTAssertEqual(model.routePlan?.total, 200)
    }

    func testSelectedCatalogProductsKeepAllOffersForDetailsAsSelectionChanges() async throws {
        let batch = CatalogImport(
            products: [CatalogProduct(id: "1", name: "First"), CatalogProduct(id: "2", name: "Second")],
            stores: [CatalogStore(id: "s1", name: "Store 1"), CatalogStore(id: "s2", name: "Store 2")],
            offers: [
                CatalogOffer(id: "o1", productID: "1", storeID: "s1", price: 85, currency: "RUB"),
                CatalogOffer(id: "o2", productID: "1", storeID: "s2", price: 95, currency: "RUB"),
                CatalogOffer(id: "o3", productID: "2", storeID: "s1", price: 80, currency: "RUB")
            ])
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 1]))
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch)), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()

        XCTAssertEqual(model.products.map(\.id), ["1"])
        let card = try XCTUnwrap(model.products.first)
        XCTAssertEqual(card.name, "First")
        XCTAssertEqual(card.lowestPrice, 100, "List cards use the plan's assigned price")
        model.showProduct(card)
        XCTAssertEqual(model.selectedProductOffer?.price, 100)
        XCTAssertEqual(model.selectedProductOffer?.storeID, "1")
        XCTAssertEqual(Set(model.selectedProduct?.offers.map(\.id) ?? []), ["o1", "o2"])
        XCTAssertEqual(model.selectedProduct?.lowestPrice, 85)
        model.dismissProduct()

        repository.selection.setQuantity(1, for: "2")
        repository.selection.setQuantity(0, for: "1")
        await repository.refresh()

        XCTAssertEqual(model.products.map(\.id), ["2"])
        let replacement = try XCTUnwrap(model.products.first)
        XCTAssertEqual(replacement.name, "Second")
        model.showProduct(replacement)
        XCTAssertEqual(model.selectedProduct?.offers.map(\.id), ["o3"])
        XCTAssertEqual(model.selectedProduct?.lowestPrice, 80)
    }

    func testDetailOfferCapturesTheCurrentPlanUntilTheNextPresentation() async throws {
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 1]))
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        let card = try XCTUnwrap(model.products.first)

        model.mode = .faster
        model.showProduct(card)
        XCTAssertEqual(model.selectedProductOffer?.price, 110, "Use the active plan, not a previously rendered card")
        model.mode = .cheaper
        repository.selection.setQuantity(2, for: "1")
        XCTAssertNil(model.plan)
        XCTAssertEqual(model.selectedProductOffer?.price, 110, "An open detail sheet keeps its offer snapshot")
        model.dismissProduct()
        XCTAssertEqual(model.selectedProductOffer?.price, 110, "Dismissing must not change the visible price")

        model.showProduct(card)
        XCTAssertNil(model.selectedProductOffer, "Do not reuse a previous selection while a plan is unavailable")
        model.dismissProduct()
        await repository.refresh()
        model.showProduct(try XCTUnwrap(model.products.first))
        XCTAssertEqual(model.selectedProductOffer?.price, 100)
    }

    func testDetailsWithoutAPlanDoNotSelectAnArbitraryCatalogStore() throws {
        let repository = ShoppingListRepository()
        let catalog = PreviewCatalogRepository.sample
        let model = ShoppingListViewModel(catalog: catalog, list: repository)
        repository.selection.setQuantity(1, for: "preview-product")

        model.showProduct(try XCTUnwrap(model.products.first))

        XCTAssertNotNil(model.selectedProduct?.lowestOffer)
        XCTAssertNil(model.selectedProductOffer)
    }

    func testSelectionEnforcesProductLimitWithoutBlockingRemovals() {
        let selection = ProductSelection()
        for number in 1...30 { selection.setQuantity(1, for: String(number)) }
        selection.setQuantity(1, for: "31")
        XCTAssertTrue(selection.showsLimitAlert)
        XCTAssertEqual(selection.quantities.count, 30)
        selection.setQuantity(150, for: "1")
        XCTAssertEqual(selection.quantity(for: "1"), 99)
        selection.setQuantity(0, for: "2")
        selection.setQuantity(1, for: "31")
        XCTAssertEqual(selection.quantity(for: "31"), 1)
    }

    func testReachabilityHintDoesNotBlockAReachableServer() async {
        let service = ControlledShoppingService(quantities: ["1": 2])
        let repository = ShoppingListRepository(service: service, cache: MemoryShoppingListCache())
        repository.updateConnectivity(isConnected: false)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()

        XCTAssertEqual(repository.selection.quantities, ["1": 2])
        XCTAssertEqual(repository.planResult?.plans.first?.total, 200)
        XCTAssertNil(repository.failure)
    }

    func testReconnectDuringFailedRequestRetriesAfterWorkerFinishes() async {
        let service = ControlledShoppingService(quantities: ["1": 2])
        let repository = ShoppingListRepository(service: service)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.pauseNextPlan()
        await service.failPausedPlan()
        let calculated = expectation(description: "Reconnected calculation")
        let observation = repository.$planResult.compactMap { $0 }.prefix(1).sink { _ in calculated.fulfill() }
        defer { observation.cancel() }
        repository.setPresented(true)
        await service.waitUntilPaused()
        repository.updateConnectivity(isConnected: false)
        repository.updateConnectivity(isConnected: true)
        await service.resume()
        await fulfillment(of: [calculated], timeout: 3)

        XCTAssertEqual(repository.planResult?.plans.first?.total, 200)
        XCTAssertNil(repository.failure)
        let maximum = await service.maximumActivePlans
        XCTAssertEqual(maximum, 1)
    }

    func testCompletedCachedCartLoadsCurrentActiveCartAndPlans() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        original.setPresented(true)
        await original.refresh()
        await service.replaceCart(quantities: ["2": 3], closesPrevious: true)

        let restored = ShoppingListRepository(service: service, cache: cache)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["2": 3])
        XCTAssertEqual(restored.planResult?.plans.first?.total, 300)
        XCTAssertNil(restored.failure)
    }

    func testPendingEditsRemainBoundWhenAnotherCartBecomesActive() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        let oldID = try XCTUnwrap(original.cart?.id)
        await service.setOffline(true)
        original.selection.setQuantity(5, for: "1")
        await original.refresh()
        await service.replaceCartKeepingPreviousActive(quantities: ["1": 7, "2": 2])
        await service.setOffline(false)
        let newestValue = try await service.activeCart()
        let newest = try XCTUnwrap(newestValue)
        let restored = ShoppingListRepository(service: service, cache: cache)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        let old = try await service.cart(id: oldID)
        let current = try await service.cart(id: newest.id)
        XCTAssertEqual(old.quantities, ["1": 5])
        XCTAssertEqual(current.quantities, ["1": 7, "2": 2])
        XCTAssertEqual(restored.selection.quantities, current.quantities)
        let targets = await service.writtenCartIDs
        XCTAssertEqual(targets, [oldID])
    }

    func testGuestEditsMergeIntoLatestCartSeparatelyFromCachedEdits() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let oldValue = try await service.activeCart()
        let old = try XCTUnwrap(oldValue)
        try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil),
                             account: ShoppingListTestAccount.make("account"))
        await service.replaceCartKeepingPreviousActive(quantities: ["1": 7, "2": 2])
        let selection = ProductSelection()
        selection.setQuantity(3, for: "1")
        let repository = ShoppingListRepository(service: service, selection: selection, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        let previous = try await service.cart(id: old.id)
        XCTAssertEqual(previous.quantities, ["1": 5])
        XCTAssertEqual(repository.selection.quantities, ["1": 3, "2": 2])
    }

    func testLateCacheReadDoesNotMixEditsForDifferentCarts() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let oldValue = try await service.activeCart()
        let old = try XCTUnwrap(oldValue)
        try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil),
                             account: ShoppingListTestAccount.make("account"))
        await service.replaceCartKeepingPreviousActive(quantities: ["1": 7])
        await cache.setFailing(true)
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        repository.selection.setQuantity(3, for: "1")
        await repository.refresh()
        await cache.setFailing(false)
        await repository.refresh()
        let previous = try await service.cart(id: old.id)
        XCTAssertEqual(previous.quantities, ["1": 5])
        XCTAssertEqual(repository.cart?.quantities, ["1": 3])
        XCTAssertFalse(repository.hasCacheFailure)
    }

    func testAcknowledgedGuestEditsDoNotMaskAnotherCartAfterLateCacheRecovery() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let otherService = ControlledShoppingService(quantities: ["1": 1])
        let otherResponse = try await otherService.activeCart()
        let otherCart = try XCTUnwrap(otherResponse)
        let cache = MemoryShoppingListCache()
        try await cache.save(.init(cart: otherCart, pending: [.cart(otherCart.id): ["1": 5]], plan: nil),
                             account: ShoppingListTestAccount.make("account"))
        await cache.setFailing(true)
        let selection = ProductSelection()
        selection.setQuantity(3, for: "1")
        let repository = ShoppingListRepository(service: service, selection: selection, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        XCTAssertEqual(repository.cart?.quantities, ["1": 3])
        await service.activateCart(otherCart)
        await repository.refresh()
        XCTAssertEqual(repository.cart?.id, otherCart.id)
        XCTAssertEqual(repository.cart?.quantities, ["1": 1])
        await cache.setFailing(false)
        await repository.refresh()
        XCTAssertEqual(repository.cart?.quantities, ["1": 5], "The unread edit belongs to this cart and must survive an edit acknowledged on another cart")
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.cart?.quantities, ["1": 5])
    }

    func testFullPreviousCartDoesNotBlockCurrentCartCalculation() async throws {
        let service = ControlledShoppingService(quantities: Dictionary(uniqueKeysWithValues: (1...29).map { (String($0), 1) }))
        let response = try await service.activeCart()
        let oldCart = try XCTUnwrap(response)
        let cache = MemoryShoppingListCache()
        try await cache.save(.init(cart: oldCart, pending: [.cart(oldCart.id): ["31": 1]], plan: nil),
                             account: ShoppingListTestAccount.make("account"))
        await service.setRemoteQuantities(Dictionary(uniqueKeysWithValues: (1...30).map { (String($0), 1) }))
        await service.replaceCartKeepingPreviousActive(quantities: ["40": 1])
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantities, ["40": 1])
        XCTAssertEqual(repository.failure, .otherCartSyncFailed)
        XCTAssertEqual(repository.planResult?.plans.first?.total, 100, "An unrelated cart's limit must not block the current cart")
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.pending[.cart(oldCart.id)]?["31"], 1)
        XCTAssertNotNil(saved?.plan)
        XCTAssertFalse(repository.hasCacheFailure)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        XCTAssertEqual(model.message, Texts.ShoppingList.otherCartSyncFailed)
        // The conflict must remain isolated on later refreshes and edits, too.
        repository.selection.setQuantity(2, for: "40")
        await repository.refresh()
        XCTAssertEqual(repository.planResult?.plans.first?.total, 200)
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "40", quantity: 2, exists: true)])
        await service.setOffline(true)
        let restored = ShoppingListRepository(service: service, cache: cache)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["40": 2])
        XCTAssertEqual(restored.planResult?.plans.first?.total, 200)
    }

    func testRejectedPreviousCartRetainsEditsAndRetriesWithoutBlockingCurrentEdits() async throws {
        for status in [409, 422, 500] {
            let service = ControlledShoppingService(quantities: ["1": 1])
            let response = try await service.activeCart()
            let old = try XCTUnwrap(response)
            let cache = MemoryShoppingListCache()
            try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil),
                                 account: ShoppingListTestAccount.make("account"))
            await service.replaceCartKeepingPreviousActive(quantities: ["2": 2])
            await service.rejectWrites(in: old.id, with: APIError.http(status: status, code: nil, requestID: nil, retryAfter: nil))
            let selection = ProductSelection()
            selection.setQuantity(3, for: "2")
            let repository = ShoppingListRepository(service: service, selection: selection, cache: cache)
            repository.setAccount(ShoppingListTestAccount.make("account"))
            repository.setPresented(true)
            await repository.refresh()
            XCTAssertEqual(repository.selection.quantities, ["2": 3])
            XCTAssertEqual(repository.planResult?.plans.first?.total, 300)
            XCTAssertEqual(repository.failure, .otherCartSyncFailed)
            let saved = await cache.snapshot("account")
            XCTAssertEqual(saved?.pending[.cart(old.id)], ["1": 5])
            XCTAssertNotNil(saved?.plan)
            XCTAssertFalse(repository.hasCacheFailure)

            await service.rejectWrites(in: old.id, with: nil)
            await repository.refresh()
            let previous = try await service.cart(id: old.id)
            XCTAssertEqual(previous.quantities, ["1": 5])
            XCTAssertEqual(repository.selection.quantities, ["2": 3])
            XCTAssertNil(repository.failure)
            let synced = await cache.snapshot("account")
            XCTAssertTrue(synced?.pending.isEmpty == true)
        }
    }

    func testPreviousCartAuthenticationConnectivityAndCancellationStillStopSynchronization() async throws {
        let errors: [(any Error, ShoppingListFailure?)] = [
            (APIError.http(status: 401, code: nil, requestID: nil, retryAfter: nil), .authenticationRequired),
            (URLError(.notConnectedToInternet), .offline),
            (CancellationError(), nil)
        ]
        for (error, expected) in errors {
            let service = ControlledShoppingService(quantities: ["1": 1])
            let response = try await service.activeCart()
            let old = try XCTUnwrap(response)
            let cache = MemoryShoppingListCache()
            try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil),
                                 account: ShoppingListTestAccount.make("account"))
            await service.replaceCartKeepingPreviousActive(quantities: ["2": 2])
            await service.rejectWrites(in: old.id, with: error)
            let repository = ShoppingListRepository(service: service, cache: cache)
            repository.setAccount(ShoppingListTestAccount.make("account"))
            repository.setPresented(true)
            await repository.refresh()
            XCTAssertEqual(repository.failure, expected)
            XCTAssertNil(repository.planResult)
            XCTAssertFalse(repository.isBusy)
            let requests = await service.planRequests
            XCTAssertEqual(requests, 0)
            let saved = await cache.snapshot("account")
            XCTAssertEqual(saved?.pending[.cart(old.id)], ["1": 5])
        }
    }

    func testLimitConflictDoesNotDisablePersistenceOfLaterOfflineEdits() async throws {
        let service = ControlledShoppingService(quantities: Dictionary(uniqueKeysWithValues: (1...29).map { (String($0), 1) }))
        let response = try await service.activeCart()
        let cart = try XCTUnwrap(response)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let account = ShoppingListTestAccount.make("account")
        try await cache.save(.init(cart: cart, pending: [.cart(cart.id): ["31": 1]], plan: nil), account: account)
        await service.setRemoteQuantities(Dictionary(uniqueKeysWithValues: (1...30).map { (String($0), 1) }))
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(account)
        await repository.refresh()
        XCTAssertEqual(repository.failure, .limit)
        XCTAssertEqual(repository.selection.quantities.count, 31)
        XCTAssertFalse(repository.hasCacheFailure, "A sync conflict is valid local state, not a disk failure")
        await service.setOffline(true)
        repository.selection.setQuantity(5, for: "2")
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantity(for: "2"), 5)
        let restored = ShoppingListRepository(service: service, cache: FileShoppingListCache(directory: folder))
        restored.setAccount(account)
        restored.setPresented(true)
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantity(for: "2"), 5, "An unrelated offline quantity change must survive relaunch while the limit conflict is unresolved")
        XCTAssertFalse(restored.hasCacheFailure)
        XCTAssertEqual(restored.selection.quantity(for: "30"), 1)
        XCTAssertEqual(restored.selection.quantity(for: "31"), 1)
        XCTAssertNil(restored.planResult)

        // Removing a product resolves the conflict; all retained edits can then synchronize.
        await service.setOffline(false)
        restored.selection.setQuantity(0, for: "3")
        await restored.refresh()
        XCTAssertNil(restored.failure)
        XCTAssertFalse(restored.hasCacheFailure)
        XCTAssertEqual(restored.cart?.items.count, 30)
        XCTAssertNil(restored.cart?.quantities["3"])
        XCTAssertEqual(restored.cart?.quantities["2"], 5)
        XCTAssertEqual(restored.cart?.quantities["31"], 1)
        XCTAssertEqual(restored.planResult?.plans.first?.total, 3400)
        let saved = try await cache.load(account: account)
        XCTAssertTrue(saved?.pending.isEmpty == true)
        XCTAssertNotNil(saved?.plan)
    }

    func testRejectedOldCartBecomingCurrentSynchronizesBeforeCalculating() async throws {
        for rejectionPersists in [true, false] {
            let service = ControlledShoppingService(quantities: ["1": 1])
            let response = try await service.activeCart()
            let old = try XCTUnwrap(response)
            let cache = MemoryShoppingListCache()
            let account = ShoppingListTestAccount.make("account")
            try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil), account: account)
            await service.replaceCartKeepingPreviousActive(quantities: ["2": 2])
            await service.rejectWrites(in: old.id, with: APIError.http(status: 422, code: nil, requestID: nil, retryAfter: nil))
            await service.pauseNextPlan()
            let repository = ShoppingListRepository(service: service, cache: cache)
            repository.setAccount(account)
            repository.setPresented(true)
            await service.waitUntilPaused()
            XCTAssertEqual(repository.failure, .otherCartSyncFailed)
            await service.activateCart(old)
            if !rejectionPersists { await service.rejectWrites(in: old.id, with: nil) }
            let refreshStarted = expectation(description: "Refresh requested during the current plan")
            let refresh = Task {
                refreshStarted.fulfill()
                await repository.refresh()
            }
            await fulfillment(of: [refreshStarted], timeout: 2)
            await service.resume()
            await refresh.value
            XCTAssertEqual(repository.cart?.id, old.id)
            XCTAssertEqual(repository.selection.quantities, ["1": 5])
            XCTAssertFalse(repository.hasCacheFailure)
            let requests = await service.planRequests
            let saved = await cache.snapshot("account")
            if rejectionPersists {
                XCTAssertNil(repository.planResult, "No calculation may use the server's old quantity of 1")
                XCTAssertEqual(requests, 1)
                XCTAssertEqual(repository.failure, .unavailable)
                XCTAssertEqual(saved?.pending[.cart(old.id)], ["1": 5])
                XCTAssertNil(saved?.plan)
            } else {
                XCTAssertEqual(repository.cart?.quantities, ["1": 5])
                XCTAssertEqual(repository.planResult?.plans.first?.total, 500)
                XCTAssertEqual(requests, 2)
                XCTAssertNil(repository.failure, "The old warning must clear when the only rejected cart recovers")
                XCTAssertTrue(saved?.pending.isEmpty == true)
                XCTAssertEqual(saved?.plan?.quantities, ["1": 5])
            }
        }
    }

    func testCurrentCartLimitStillPreventsCalculatingUnsynchronizedQuantities() async throws {
        let service = ControlledShoppingService(quantities: Dictionary(uniqueKeysWithValues: (1...29).map { (String($0), 1) }))
        let response = try await service.activeCart()
        let cart = try XCTUnwrap(response)
        let cache = MemoryShoppingListCache()
        try await cache.save(.init(cart: cart, pending: [.cart(cart.id): ["31": 1]], plan: nil),
                             account: ShoppingListTestAccount.make("account"))
        await service.setRemoteQuantities(Dictionary(uniqueKeysWithValues: (1...30).map { (String($0), 1) }))
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        XCTAssertEqual(repository.failure, .limit)
        XCTAssertNil(repository.planResult)
        let requests = await service.planRequests
        XCTAssertEqual(requests, 0)
        let writes = await service.writes
        XCTAssertTrue(writes.isEmpty)
    }

    func testLateUnboundCacheDoesNotOverrideAcknowledgedCurrentCartEdits() async throws {
        let cache = MemoryShoppingListCache()
        let account = ShoppingListTestAccount.make("account")
        try await cache.save(.init(cart: nil, pending: [.active: ["1": 5]], plan: nil), account: account)
        await cache.setFailing(true)
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(account)
        await repository.refresh()
        repository.selection.setQuantity(3, for: "1")
        await repository.refresh()
        await cache.setFailing(false)
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantities, ["1": 3])
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "1", quantity: 3, exists: true)])
    }

    func testUnavailableCartRetainsEditsWithoutBlockingCurrentPlan() async throws {
        for completed in [true, false] {
            let cache = MemoryShoppingListCache()
            let service = ControlledShoppingService(quantities: ["1": 1])
            let oldValue = try await service.activeCart()
            let old = try XCTUnwrap(oldValue)
            try await cache.save(.init(cart: old, pending: [.cart(old.id): ["1": 5]], plan: nil),
                                 account: ShoppingListTestAccount.make("account"))
            await service.replaceCart(quantities: ["2": 2], closesPrevious: completed)
            let repository = ShoppingListRepository(service: service, cache: cache)
            repository.setAccount(ShoppingListTestAccount.make("account"))
            repository.setPresented(true)
            await repository.refresh()
            XCTAssertEqual(repository.selection.quantities, ["2": 2])
            XCTAssertEqual(repository.failure, .cartUnavailable)
            XCTAssertEqual(repository.planResult?.plans.first?.total, 200)
            let saved = await cache.snapshot("account")
            XCTAssertEqual(saved?.pending[.cart(old.id)], ["1": 5])
            XCTAssertNotNil(saved?.plan)
            let writes = await service.writes
            XCTAssertTrue(writes.isEmpty)
            XCTAssertFalse(repository.hasCacheFailure)
            await service.setOffline(true)
            let restored = ShoppingListRepository(service: service, cache: cache)
            restored.setAccount(ShoppingListTestAccount.make("account"))
            restored.setPresented(true)
            await restored.refresh()
            XCTAssertEqual(restored.selection.quantities, ["2": 2])
            XCTAssertEqual(restored.planResult?.plans.first?.total, 200)
        }
    }

    func testAmbiguousWriteToOldCartIsNotReplayedIntoLatestCart() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService()
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        let oldID = try XCTUnwrap(repository.cart?.id)
        await service.failAfterNextWrite()
        repository.selection.setQuantity(5, for: "1")
        await repository.refresh()
        await service.replaceCartKeepingPreviousActive(quantities: ["1": 7])
        let restarted = ShoppingListRepository(service: service, cache: cache)
        restarted.setAccount(ShoppingListTestAccount.make("account"))
        await restarted.refresh()
        XCTAssertEqual(restarted.selection.quantities, ["1": 7])
        let targets = await service.writtenCartIDs
        XCTAssertEqual(targets, [oldID])
        let snapshot = await cache.snapshot("account")
        XCTAssertTrue(snapshot?.pending.isEmpty == true)
    }

    func testFailedLogoutCleanupCannotReplayEditsInNewSessionAfterRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let cache = FileShoppingListCache(directory: folder)
        let service = ControlledShoppingService(quantities: ["1": 1])
        let oldAccount = ShoppingListTestAccount.make("account")
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(oldAccount)
        await original.refresh()
        await service.setOffline(true)
        original.selection.setQuantity(5, for: "1")
        await original.refresh()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        original.setAccount(nil)
        await original.refresh()
        XCTAssertTrue(original.hasCacheFailure)
        await service.setOffline(false)
        let newAccount = ShoppingListTestAccount.make("account", sessionID: UUID())
        let restarted = ShoppingListRepository(service: service, cache: FileShoppingListCache(directory: folder))
        restarted.setAccount(newAccount)
        await restarted.refresh()
        XCTAssertEqual(restarted.selection.quantities, ["1": 1])
        let writes = await service.writes
        XCTAssertTrue(writes.isEmpty)
        XCTAssertTrue(restarted.hasCacheFailure)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        await restarted.refresh()
        let current = try await cache.load(account: newAccount)
        XCTAssertEqual(current?.cart?.quantities, ["1": 1])
        // A delayed retry from the original repository must not remove the newer snapshot.
        await original.refresh()
        let retained = try await cache.load(account: newAccount)
        XCTAssertNotNil(retained)
    }

    func testNewSessionOfSameAccountClearsPresentedPersonalState() async throws {
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 1]))
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        model.routePlan = try XCTUnwrap(model.plan)
        model.showProduct(try XCTUnwrap(model.products.first))
        repository.setAccount(ShoppingListTestAccount.make("account", sessionID: UUID()))
        XCTAssertNil(model.routePlan)
        XCTAssertNil(model.selectedProduct)
        XCTAssertTrue(repository.selection.quantities.isEmpty)
        await repository.refresh()
    }

    func testOfflineEditsSurviveReadFailureWhenServerIsReachable() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let response = try await service.activeCart()
        let cart = try XCTUnwrap(response)
        try await cache.save(.init(cart: cart, pending: [.cart(try XCTUnwrap(cart).id): ["1": 5]], plan: nil), account: ShoppingListTestAccount.make("account"))
        await cache.setFailing(true)
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        XCTAssertTrue(repository.hasCacheFailure)
        await cache.setFailing(false)
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantity(for: "1"), 5, "Retry must restore the unread offline edit")
        XCTAssertEqual(repository.cart?.quantities["1"], 5, "The recovered edit must reach the server")
    }

    func testStartupSelectsLatestActiveCartInsteadOfCachedActiveCart() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        await service.replaceCartKeepingPreviousActive(quantities: ["2": 3])
        let response = try await service.activeCart()
        let newest = try XCTUnwrap(response)
        let restored = ShoppingListRepository(service: service, cache: cache)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertEqual(restored.cart?.id, newest.id, "A cached cart must not override the current active cart")
        XCTAssertEqual(restored.selection.quantities, ["2": 3])
    }

    func testFailedLogoutCleanupDoesNotReplayDiscardedEditsOnSignIn() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        await service.setOffline(true)
        original.selection.setQuantity(5, for: "1")
        await original.refresh()
        await cache.setRemovalFailing(true)
        original.setAccount(nil)
        await original.refresh()
        XCTAssertTrue(original.hasCacheFailure)
        await cache.setRemovalFailing(false)
        await service.setOffline(false)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        XCTAssertEqual(original.selection.quantity(for: "1"), 1, "Discarded edits must not return after logout")
        let writes = await service.writes
        XCTAssertTrue(writes.isEmpty, "Reauthentication must not silently resend discarded edits")
    }

    func testAcknowledgedEditsOverrideUnreadCacheWhenStorageRecovers() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1, "2": 2])
        let cache = MemoryShoppingListCache()
        let cart = try await service.activeCart()
        try await cache.save(.init(cart: cart, pending: [.cart(try XCTUnwrap(cart).id): ["1": 5, "2": 4]], plan: nil), account: ShoppingListTestAccount.make("account"))
        await cache.setFailing(true)
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        repository.selection.setQuantity(3, for: "1")
        repository.selection.setQuantity(0, for: "2")
        await repository.refresh()
        XCTAssertEqual(repository.cart?.quantities, ["1": 3])

        // Acknowledged local intent masks old disk edits; it must not replay over a newer server change.
        await service.setRemoteQuantities(["1": 7])
        await cache.setFailing(false)
        await repository.refresh()

        XCTAssertEqual(repository.selection.quantities, ["1": 7])
        XCTAssertEqual(repository.planResult?.plans.first?.total, 700)
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.cart?.quantities, ["1": 7])
        XCTAssertTrue(saved?.pending.isEmpty == true)
        XCTAssertFalse(repository.hasCacheFailure)
    }

    func testFailedCleanupBlocksCacheReadsButNotNetworkOrNewEdits() async throws {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.setOffline(true)
        repository.selection.setQuantity(5, for: "1")
        await repository.refresh()
        await cache.setRemovalFailing(true)
        repository.setAccount(nil)
        await repository.refresh()
        await service.setOffline(false)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantities, ["1": 1])
        XCTAssertTrue(repository.hasCacheFailure)
        repository.selection.setQuantity(2, for: "1")
        await repository.refresh()
        XCTAssertEqual(repository.cart?.quantities, ["1": 2])

        await cache.setRemovalFailing(false)
        await repository.refresh()

        XCTAssertEqual(repository.selection.quantities, ["1": 2])
        XCTAssertFalse(repository.hasCacheFailure)
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.cart?.quantities, ["1": 2])
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "1", quantity: 2, exists: true)])
    }

    func testAnotherAccountSavingDoesNotHideFailedLogoutCleanup() async {
        let cache = MemoryShoppingListCache()
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 1]), cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("first"))
        await repository.refresh()
        await cache.setRemovalFailing(true)
        repository.setAccount(ShoppingListTestAccount.make("second"))
        await repository.refresh()
        let second = await cache.snapshot("second")
        XCTAssertNotNil(second?.cart)
        XCTAssertTrue(repository.hasCacheFailure)

        await cache.setRemovalFailing(false)
        await repository.refresh()
        let first = await cache.snapshot("first")
        XCTAssertNil(first)
        XCTAssertFalse(repository.hasCacheFailure)
    }

    func testSavedCalculationRemainsLabelledWhileRefreshing() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let cache = MemoryShoppingListCache()
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        original.setPresented(true)
        await original.refresh()
        await service.setOffline(true)
        let restored = ShoppingListRepository(service: service, cache: cache)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()
        await service.setOffline(false)
        await service.pauseNextPlan()
        let refresh = Task { await restored.refresh() }
        await service.waitUntilPaused()
        XCTAssertTrue(restored.isBusy)
        XCTAssertNotNil(model.plan)
        XCTAssertEqual(model.message, Texts.ShoppingList.cachedCalculation)
        await service.resume()
        await refresh.value
        XCTAssertFalse(restored.isPlanCached)
        XCTAssertNil(model.message)
    }

    func testOfflineRelaunchRestoresCartAndPreviouslyCalculatedPlans() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        original.setPresented(true)
        await original.refresh()
        let planID = try XCTUnwrap(original.planResult?.plans.first?.id)

        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()

        XCTAssertEqual(restored.selection.quantities, ["1": 2])
        XCTAssertEqual(restored.cart?.items.first?.product.name, "Product 1")
        XCTAssertEqual(restored.planResult?.plans.first?.id, planID)
        XCTAssertTrue(restored.isPlanCached)
        XCTAssertEqual(restored.failure, .offline)
        XCTAssertFalse(restored.isBusy)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        XCTAssertEqual(model.products.first?.lowestPrice, 100)
        XCTAssertEqual(model.message, Texts.ShoppingList.cachedCalculation)
    }

    func testOfflineRelaunchDoesNotInventAPreviousCalculation() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()

        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()

        XCTAssertEqual(restored.selection.quantities, ["1": 2])
        XCTAssertNil(restored.planResult)
        let calls = await service.planRequests
        XCTAssertEqual(calls, 0)
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: restored)
        XCTAssertNil(model.message)
    }

    func testFailedRefreshPreservesCalculationOnlyForTheSameCart() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        let planID = repository.planResult?.plans.first?.id
        await service.setOffline(true)
        repository.updateConnectivity(isConnected: false)
        await repository.refresh()
        XCTAssertEqual(repository.planResult?.plans.first?.id, planID)

        await service.replaceCart(quantities: ["2": 3])
        await service.failPlans()
        await service.setOffline(false)
        repository.updateConnectivity(isConnected: true)
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantities, ["2": 3])
        XCTAssertNil(repository.planResult)
        let snapshot = await cache.snapshot("account")
        XCTAssertNil(snapshot?.plan)
    }

    func testOfflineEditsSurviveRelaunchInvalidatePlansAndSyncAsAbsoluteQuantities() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1, "2": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        original.setPresented(true)
        await original.refresh()
        await service.setOffline(true)
        original.updateConnectivity(isConnected: false)
        original.selection.setQuantity(4, for: "1")
        original.selection.setQuantity(0, for: "2")
        await original.refresh()
        XCTAssertNil(original.planResult)

        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        restored.setPresented(true)
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["1": 4])
        XCTAssertNil(restored.planResult)

        await service.setOffline(false)
        restored.updateConnectivity(isConnected: true)
        await restored.refresh()
        XCTAssertEqual(restored.cart?.quantities, ["1": 4])
        XCTAssertEqual(restored.planResult?.plans.first?.total, 400)
        XCTAssertFalse(restored.isPlanCached)
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "2", quantity: 0, exists: true), .init(id: "1", quantity: 4, exists: true)])
    }

    func testCachedPendingAddDoesNotReplayAnAmbiguousPOSTAfterRelaunch() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService()
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        await service.failAfterNextWrite()
        original.selection.setQuantity(3, for: "1")
        await original.refresh()
        XCTAssertEqual(original.failure, .offline)

        let restored = ShoppingListRepository(service: service, cache: cache)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["1": 3])
        let writes = await service.writes
        XCTAssertEqual(writes.count, 1)
        let saved = await cache.snapshot("account")
        XCTAssertTrue(saved?.pending.isEmpty == true)
    }

    func testEditsDuringSlowCacheLoadTakePrecedence() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        await cache.pauseNextLoad()

        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await cache.waitUntilPaused()
        restored.selection.setQuantity(5, for: "1")
        await cache.resume()
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["1": 5])
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.pending.values.first, ["1": 5])
    }

    func testLogoutRemovesCacheAfterAnInFlightSave() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("first"))
        await repository.refresh()
        await service.setOffline(true)
        repository.updateConnectivity(isConnected: false)
        await cache.pauseNextSave()
        repository.selection.setQuantity(4, for: "1")
        await cache.waitUntilPaused()
        repository.setAccount(nil)
        XCTAssertFalse(repository.hasCacheFailure, "Queued cleanup is not a storage failure")
        await cache.resume()
        await repository.refresh()
        let saved = await cache.snapshot("first")
        XCTAssertNil(saved)
        XCTAssertTrue(repository.selection.quantities.isEmpty)

        repository.setAccount(ShoppingListTestAccount.make("second"))
        await repository.refresh()
        XCTAssertTrue(repository.selection.quantities.isEmpty)
        XCTAssertNil(repository.planResult)
    }

    func testAccountChangeRejectsLateCacheLoad() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("first"))
        await original.refresh()
        await cache.pauseNextLoad()
        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("first"))
        await cache.waitUntilPaused()
        restored.setAccount(ShoppingListTestAccount.make("second"))
        await cache.resume()
        await restored.refresh()
        XCTAssertEqual(restored.accountID, "second")
        XCTAssertTrue(restored.selection.quantities.isEmpty)
        XCTAssertNil(restored.planResult)
    }

    func testCacheFailureDoesNotBlockNetworkAndRetryRecoversStorage() async {
        let cache = MemoryShoppingListCache()
        await cache.setFailing(true)
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 2]), cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        repository.setPresented(true)
        await repository.refresh()
        XCTAssertEqual(repository.planResult?.plans.first?.total, 200)
        XCTAssertNil(repository.failure)
        XCTAssertTrue(repository.hasCacheFailure)
        await cache.setFailing(false)
        await repository.refresh()
        XCTAssertFalse(repository.hasCacheFailure)
        let saved = await cache.snapshot("account")
        XCTAssertNotNil(saved?.plan)
    }

    func testQueuedCacheWritesKeepTheLatestEdit() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service, cache: cache)
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.setOffline(true)
        repository.updateConnectivity(isConnected: false)
        await cache.pauseNextSave()
        repository.selection.setQuantity(2, for: "1")
        await cache.waitUntilPaused()
        repository.selection.setQuantity(3, for: "1")
        repository.selection.setQuantity(4, for: "1")
        await cache.resume()
        await repository.refresh()
        let saved = await cache.snapshot("account")
        XCTAssertEqual(saved?.pending.values.first, ["1": 4])
        XCTAssertFalse(repository.isBusy)
    }

    func testOfflineCacheReadFailureCanBeRetriedWithoutOverwritingTheSavedCart() async {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 2])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        await original.refresh()
        await cache.setFailing(true)
        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertTrue(restored.hasCacheFailure)
        XCTAssertTrue(restored.selection.quantities.isEmpty)
        await cache.setFailing(false)
        await restored.refresh()
        XCTAssertFalse(restored.hasCacheFailure)
        XCTAssertEqual(restored.selection.quantities, ["1": 2])
    }

    func testReconnectReloadsRemoteChangesBeforeSendingAnOfflineAdd() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service, cache: MemoryShoppingListCache())
        repository.setAccount(ShoppingListTestAccount.make("account"))
        await repository.refresh()
        await service.setOffline(true)
        repository.updateConnectivity(isConnected: false)
        repository.selection.setQuantity(3, for: "2")
        await service.setRemoteQuantities(["1": 1, "2": 5])
        await service.pauseNextWrite()
        await service.setOffline(false)
        repository.updateConnectivity(isConnected: true)
        await service.waitUntilPaused()
        await service.resume()
        await repository.refresh()
        XCTAssertEqual(repository.selection.quantity(for: "2"), 3)
        let writes = await service.writes
        XCTAssertEqual(writes, [.init(id: "2", quantity: 3, exists: true)])
    }

    func testChangedOriginRestoresProductsButDropsOldCalculation() async throws {
        let cache = MemoryShoppingListCache()
        let service = ControlledShoppingService(quantities: ["1": 1])
        let original = ShoppingListRepository(service: service, cache: cache)
        original.setAccount(ShoppingListTestAccount.make("account"))
        original.setPresented(true)
        await original.refresh()
        let value = await cache.snapshot("account")
        var snapshot = try XCTUnwrap(value)
        let saved = try XCTUnwrap(snapshot.plan)
        snapshot.plan = CachedShoppingPlan(cartID: saved.cartID, quantities: saved.quantities,
                                          origin: .init(latitude: 0, longitude: 0), calculatedAt: saved.calculatedAt, result: saved.result)
        try await cache.save(snapshot, account: ShoppingListTestAccount.make("account"))

        let restored = ShoppingListRepository(service: service, cache: cache)
        await service.setOffline(true)
        restored.updateConnectivity(isConnected: false)
        restored.setAccount(ShoppingListTestAccount.make("account"))
        await restored.refresh()
        XCTAssertEqual(restored.selection.quantities, ["1": 1])
        XCTAssertNil(restored.planResult)
        XCTAssertFalse(restored.isPlanCached)
    }
}

private actor ControlledShoppingService: ShoppingListService {
    struct Write: Equatable, Sendable {
        let id: String
        let quantity: Int
        let exists: Bool
    }
    private var value: ShoppingCart
    private var inactiveCart: ShoppingCart?
    private var previousActiveCart: ShoppingCart?
    private var offline = false
    private var failsPausedPlan = false
    private let baselinePrice: Decimal?
    private let fastUnitPrice: Decimal
    private var hasCart = true
    private var failCreate = false
    private(set) var creates = 0
    private(set) var writes: [Write] = []
    private(set) var writtenCartIDs: [UUID] = []
    private var failWrite = false
    private var writeErrors: [UUID: any Error] = [:]
    private var pauseWrite = false
    private var pausePlan = false
    private var noPlans = false
    private var planFails = false
    private var pause: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private var reachedPause = false
    private var activePlans = 0
    private(set) var maximumActivePlans = 0
    private(set) var planRequests = 0

    init(quantities: [String: Int] = [:], baselinePrice: Decimal? = nil, fastUnitPrice: Decimal = 110) {
        value = Self.cart(quantities)
        self.baselinePrice = baselinePrice
        self.fastUnitPrice = fastUnitPrice
    }
    func setOffline(_ value: Bool) { offline = value }
    private func checkConnection() throws {
        if offline { throw URLError(.notConnectedToInternet) }
    }
    func activeCart() throws -> ShoppingCart? {
        try checkConnection()
        return hasCart ? value : nil
    }
    func cart(id: UUID) throws -> ShoppingCart {
        try checkConnection()
        if let previousActiveCart, previousActiveCart.id == id { return previousActiveCart }
        if let inactiveCart, inactiveCart.id == id { return inactiveCart }
        guard value.id == id else { throw APIError.http(status: 404, code: nil, requestID: nil, retryAfter: nil) }
        return value
    }
    func createCart(name: String) throws -> ShoppingCart {
        try checkConnection()
        creates += 1
        hasCart = true
        if failCreate { failCreate = false; throw URLError(.networkConnectionLost) }
        return value
    }
    func startWithoutCart() { hasCart = false }
    func failAfterNextCreate() { failCreate = true }
    func replaceCart(quantities: [String: Int], closesPrevious: Bool = false) {
        if closesPrevious {
            inactiveCart = ShoppingCart(id: value.id, name: value.name, status: "completed", items: value.items)
        }
        value = Self.cart(quantities)
    }
    func replaceCartKeepingPreviousActive(quantities: [String: Int]) {
        previousActiveCart = value
        value = Self.cart(quantities)
    }
    func activateCart(_ cart: ShoppingCart) {
        inactiveCart = ShoppingCart(id: value.id, name: value.name, status: "completed", items: value.items)
        if previousActiveCart?.id == cart.id { previousActiveCart = nil }
        value = cart
    }
    func rejectWrites(in cartID: UUID, with error: (any Error)?) { writeErrors[cartID] = error }
    func setRemoteQuantities(_ quantities: [String: Int]) {
        value = Self.cart(quantities, id: value.id)
    }
    func pauseNextWrite() { pauseWrite = true; reachedPause = false }
    func pauseNextPlan() { pausePlan = true; reachedPause = false }
    func failAfterNextWrite() { failWrite = true }
    func returnNoPlans() { noPlans = true }
    func failPlans() { planFails = true }
    func failPausedPlan() { failsPausedPlan = true }

    func waitUntilPaused() async {
        if reachedPause { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { pause?.resume(); pause = nil }
    private func suspend() async {
        reachedPause = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { pause = $0 }
    }

    func updateItem(cartID: UUID, productID: String, quantity: Int, exists: Bool) async throws -> ShoppingCart {
        try checkConnection()
        if let error = writeErrors[cartID] { throw error }
        writes.append(Write(id: productID, quantity: quantity, exists: exists))
        writtenCartIDs.append(cartID)
        let target = previousActiveCart?.id == cartID ? previousActiveCart! : value
        var quantities = target.quantities
        if quantity == 0 { quantities[productID] = nil }
        else { quantities[productID] = exists ? quantity : quantities[productID, default: 0] + quantity }
        let response = Self.cart(quantities, id: target.id)
        if previousActiveCart?.id == cartID { previousActiveCart = response }
        else { value = response }
        if pauseWrite { pauseWrite = false; await suspend() }
        if failWrite { failWrite = false; throw URLError(.networkConnectionLost) }
        return response
    }

    func plans(cartID: UUID, start: ShoppingCoordinate) async throws -> ShoppingPlanResult {
        try checkConnection()
        planRequests += 1
        if planFails { throw URLError(.notConnectedToInternet) }
        activePlans += 1
        maximumActivePlans = max(maximumActivePlans, activePlans)
        defer { activePlans -= 1 }
        let captured = value
        if pausePlan { pausePlan = false; await suspend() }
        if failsPausedPlan { failsPausedPlan = false; throw URLError(.networkConnectionLost) }
        if noPlans { return ShoppingPlanResult(plans: [], baselinePrice: nil, problem: "items_unavailable", isSynthetic: false) }
        let cheap = Self.plan(captured, price: 100, seconds: 1080)
        let fast = Self.plan(captured, price: fastUnitPrice, seconds: 780)
        return ShoppingPlanResult(plans: [cheap, fast], baselinePrice: baselinePrice ?? fast.total, problem: nil, isSynthetic: false)
    }

    private static func cart(_ quantities: [String: Int], id: UUID = UUID()) -> ShoppingCart {
        ShoppingCart(id: id, name: "List", status: "active", items: quantities.sorted { $0.key < $1.key }.map {
            ShoppingCartItem(product: CatalogProduct(id: $0.key, name: "Product " + $0.key, packageQuantity: 1, packageUnit: "pcs"), quantity: $0.value)
        })
    }

    private static func plan(_ cart: ShoppingCart, price: Decimal, seconds: Int) -> ShoppingPlan {
        let items = cart.items.map { ShoppingPlanItem(product: $0.product, quantity: $0.quantity, unitPrice: price, cardPrice: nil, priceConditions: nil) }
        let total = items.reduce(Decimal.zero) { $0 + $1.unitPrice * Decimal($1.quantity) }
        let stop = ShoppingPlanStop(position: 1, store: CatalogStore(id: "1", name: "Store"), items: items, subtotal: total)
        return ShoppingPlan(id: UUID(), total: total, savings: 0, totalSeconds: seconds, walkingMeters: 800, stops: [stop],
                            points: [], usesRoadNetwork: true, isSynthetic: false)
    }
}

private actor MemoryShoppingListCache: ShoppingListCache {
    private var values: [ShoppingListAccount: ShoppingListCacheSnapshot] = [:]
    private var failing = false
    private var removalFailing = false
    private var pauseLoad = false
    private var pauseSave = false
    private var reachedPause = false
    private var pause: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func snapshot(_ accountID: String) -> ShoppingListCacheSnapshot? { values[ShoppingListTestAccount.make(accountID)] }
    func setFailing(_ value: Bool) { failing = value }
    func setRemovalFailing(_ value: Bool) { removalFailing = value }
    func pauseNextLoad() { pauseLoad = true; reachedPause = false }
    func pauseNextSave() { pauseSave = true; reachedPause = false }

    func load(account: ShoppingListAccount) async throws -> ShoppingListCacheSnapshot? {
        if failing { throw ShoppingListCacheError.invalidSnapshot }
        let captured = values[account]
        if pauseLoad { pauseLoad = false; await suspend() }
        return captured
    }
    func save(_ snapshot: ShoppingListCacheSnapshot, account: ShoppingListAccount) async throws {
        if failing { throw ShoppingListCacheError.invalidSnapshot }
        try snapshot.validate()
        if pauseSave { pauseSave = false; await suspend() }
        values[account] = snapshot
    }
    func remove(account: ShoppingListAccount) throws {
        if removalFailing { throw ShoppingListCacheError.invalidSnapshot }
        values[account] = nil
    }
    func waitUntilPaused() async {
        if reachedPause { return }
        await withCheckedContinuation { observer = $0 }
    }
    func resume() { pause?.resume(); pause = nil }
    private func suspend() async {
        reachedPause = true
        observer?.resume()
        observer = nil
        await withCheckedContinuation { pause = $0 }
    }
}

nonisolated enum ShoppingListTestAccount {
    static let sessionID = UUID(uuidString: "2B0E1C64-ABFD-4B91-9C42-4133AC0B149E")!
    static func make(_ id: String, sessionID: UUID = sessionID) -> ShoppingListAccount {
        ShoppingListAccount(id: id, sessionID: sessionID)
    }
}
