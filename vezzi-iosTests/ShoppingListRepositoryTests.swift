import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingListRepositoryTests: XCTestCase {
    func testEmptyAccountCreatesCartOnlyOnFirstEditAndRecoversLostCreateResponse() async {
        let service = ControlledShoppingService()
        await service.startWithoutCart()
        let repository = ShoppingListRepository(service: service)
        repository.setAccount("account")
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

    func testRestoreMergesGuestEditsWithoutClearingServerProductsOrHaptics() async {
        let service = ControlledShoppingService(quantities: ["1": 2])
        let selection = ProductSelection()
        selection.setQuantity(3, for: "2")
        let feedback = selection.feedbackRevision
        let repository = ShoppingListRepository(service: service, selection: selection)
        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("first")
        await repository.refresh()
        await service.pauseNextWrite()
        repository.selection.setQuantity(2, for: "1")
        await service.waitUntilPaused()
        await service.replaceCart(quantities: ["2": 7])
        repository.setAccount("second")
        await repository.refresh()
        await service.resume()
        await Task.yield()
        XCTAssertEqual(repository.selection.quantities, ["2": 7])
        XCTAssertEqual(repository.accountID, "second")
    }

    func testPlansWaitForWritesAndObsoleteCalculationCannotReplaceNewerCart() async {
        let service = ControlledShoppingService(quantities: ["1": 1])
        let repository = ShoppingListRepository(service: service)
        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("account")
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
            repository.setAccount("account")
            repository.setPresented(true)
            await repository.refresh()

            XCTAssertEqual(model.priceSavings, expectedSavings)
        }
    }

    func testLogoutClearsPresentedRouteSynchronously() async throws {
        let repository = ShoppingListRepository(service: ControlledShoppingService(quantities: ["1": 2]))
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        repository.setAccount("first")
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
        repository.setAccount("first")
        repository.setPresented(true)
        await repository.refresh()
        // The view model may be created after the account has already been restored.
        let model = ShoppingListViewModel(catalog: PreviewCatalogRepository(), list: repository)
        model.routePlan = try XCTUnwrap(model.plan)
        model.showProduct(try XCTUnwrap(model.products.first))

        await service.replaceCart(quantities: ["2": 1])
        repository.setAccount("second")

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
        repository.setAccount("account")
        repository.setPresented(true)
        await repository.refresh()
        let presented = try XCTUnwrap(model.plan)
        model.routePlan = presented

        repository.setAccount("account")
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
        repository.setAccount("account")
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
        repository.setAccount("account")
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
}

private actor ControlledShoppingService: ShoppingListService {
    struct Write: Equatable, Sendable {
        let id: String
        let quantity: Int
        let exists: Bool
    }
    private var value: ShoppingCart
    private let baselinePrice: Decimal?
    private let fastUnitPrice: Decimal
    private var hasCart = true
    private var failCreate = false
    private(set) var creates = 0
    private(set) var writes: [Write] = []
    private var failWrite = false
    private var pauseWrite = false
    private var pausePlan = false
    private var noPlans = false
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
    func activeCart() -> ShoppingCart? { hasCart ? value : nil }
    func cart(id: UUID) -> ShoppingCart { value }
    func createCart(name: String) throws -> ShoppingCart {
        creates += 1
        hasCart = true
        if failCreate { failCreate = false; throw URLError(.networkConnectionLost) }
        return value
    }
    func startWithoutCart() { hasCart = false }
    func failAfterNextCreate() { failCreate = true }
    func replaceCart(quantities: [String: Int]) { value = Self.cart(quantities) }
    func pauseNextWrite() { pauseWrite = true; reachedPause = false }
    func pauseNextPlan() { pausePlan = true; reachedPause = false }
    func failAfterNextWrite() { failWrite = true }
    func returnNoPlans() { noPlans = true }

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
        writes.append(Write(id: productID, quantity: quantity, exists: exists))
        var quantities = value.quantities
        if quantity == 0 { quantities[productID] = nil }
        else { quantities[productID] = exists ? quantity : quantities[productID, default: 0] + quantity }
        value = Self.cart(quantities, id: value.id)
        let response = value
        if pauseWrite { pauseWrite = false; await suspend() }
        if failWrite { failWrite = false; throw URLError(.networkConnectionLost) }
        return response
    }

    func plans(cartID: UUID, start: ShoppingCoordinate) async -> ShoppingPlanResult {
        planRequests += 1
        activePlans += 1
        maximumActivePlans = max(maximumActivePlans, activePlans)
        defer { activePlans -= 1 }
        let captured = value
        if pausePlan { pausePlan = false; await suspend() }
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
