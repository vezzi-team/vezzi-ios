import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testCheaperModeGroupsProductsAndSortsEachShelfByPrice() {
        let model = mockViewModel()
        XCTAssertEqual(model.sections.map(\.id), SearchMockData.groupOrder)
        let bread = model.sections.first { $0.id == "bread" }
        XCTAssertEqual(bread?.products.map(\.lowestPrice), [55, 59, 65])
        XCTAssertTrue(model.sections.allSatisfy { $0.storeID == nil && $0.products.count == 3 })
        XCTAssertTrue(model.sections.flatMap(\.products).allSatisfy { $0.offers.count == 2 })
    }

    func testFasterModeOrdersStoresAndUsesOnlyTheirOwnPrices() {
        let model = mockViewModel()
        model.mode = .faster
        XCTAssertEqual(model.sections.map(\.id), ["pyaterochka", "perekrestok"])
        XCTAssertEqual(model.sections.compactMap(\.walkingMinutes), [5, 15])
        XCTAssertEqual(model.sections.map { $0.products.count }, [18, 18])
        for section in model.sections {
            XCTAssertTrue(section.products.allSatisfy { $0.offers.count == 1 && $0.offers.first?.storeID == section.storeID })
        }
        let firstMilk = model.sections[0].products.first { $0.id == "milk" }
        let secondMilk = model.sections[1].products.first { $0.id == "milk" }
        XCTAssertEqual(firstMilk?.lowestPrice, 99)
        XCTAssertEqual(secondMilk?.lowestPrice, 109)
        model.showProduct(secondMilk!, storeID: "perekrestok")
        let alternatives = model.relatedProducts
        XCTAssertEqual(alternatives.count, 2)
        XCTAssertTrue(alternatives.allSatisfy { $0.offers.first?.storeID == "perekrestok" })
    }

    func testBrandSearchDoesNotHideAlternativesInEitherMode() async throws {
        let model = mockViewModel()
        model.query = Texts.Product.Mock.milkBrand
        _ = await publishedItems(model.$items.eraseToAnyPublisher(), where: { $0.count == 1 })
        let milk = try XCTUnwrap(model.sections.first?.products.first)
        XCTAssertEqual(milk.id, "milk")
        model.showProduct(milk)
        XCTAssertEqual(Set(model.relatedProducts.map(\.id)), ["milk-domik", "milk-kubanskaya"])
        XCTAssertTrue(model.relatedProducts.allSatisfy { $0.offers.count == 2 })
        model.dismissProduct()

        model.mode = .faster
        let storeMilk = try XCTUnwrap(model.sections.first { $0.storeID == "perekrestok" }?.products.first)
        model.showProduct(storeMilk, storeID: "perekrestok")
        XCTAssertEqual(Set(model.relatedProducts.map(\.id)), ["milk-domik", "milk-kubanskaya"])
        XCTAssertTrue(model.relatedProducts.allSatisfy { $0.offers.count == 1 && $0.offers[0].storeID == "perekrestok" })
        XCTAssertEqual(model.query, Texts.Product.Mock.milkBrand)
    }

    func testMultipleStoreOffersProduceOneCardAndRetainTheChosenOfferID() throws {
        var batch = CatalogFixtures.catalog()
        batch.offers = [
            CatalogOffer(id: "regular", productID: "p1", storeID: "s1", price: 100, currency: "RUB", inStock: true),
            CatalogOffer(id: "discount-b", productID: "p1", storeID: "s1", price: Decimal(string: "90.25")!, currency: "RUB", inStock: true),
            CatalogOffer(id: "discount-a", productID: "p1", storeID: "s1", price: Decimal(string: "90.25")!, currency: "RUB", inStock: true),
            CatalogOffer(id: "unavailable", productID: "p1", storeID: "s1", price: 50, currency: "RUB", inStock: false)
        ]
        let snapshot = try CatalogFixtures.snapshot(batch)
        let model = SearchViewModel(repository: PreviewCatalogRepository(snapshot: snapshot))
        XCTAssertEqual(model.items.first?.offers.count, 4, "The underlying catalog retains every offer")
        for mode in ProductSearchMode.allCases {
            model.mode = mode
            let products = model.sections.flatMap(\.products)
            XCTAssertEqual(products.count, 1)
            XCTAssertEqual(products.first?.offers.count, 1)
            XCTAssertEqual(products.first?.offers.first?.id, "discount-a")
            XCTAssertEqual(products.first?.offers.first?.storeID, "s1")
            XCTAssertEqual(products.first?.lowestPrice, Decimal(string: "90.25"))
        }
    }

    func testUnavailableOffersRemainInDetailsButAreExcludedFromFasterMode() throws {
        var batch = CatalogFixtures.catalog()
        batch.offers[0].inStock = false
        let model = SearchViewModel(repository: PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch)))
        XCTAssertEqual(model.sections.first?.products.first?.offers.first?.inStock, false)
        model.mode = .faster
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testClosingOrReplacingDetailsCancelsPendingAlternatives() throws {
        let repository = ControlledRelatedCatalogRepository()
        let model = SearchViewModel(repository: repository)
        let milk = try XCTUnwrap(model.items.first { $0.id == "milk" })
        let bread = try XCTUnwrap(model.sections.flatMap(\.products).first { $0.id == "bread" })
        let product = try XCTUnwrap(model.sections.flatMap(\.products).first { $0.id == milk.id })
        model.showProduct(product)
        let oldResponse = repository.responses[0]
        model.showProduct(bread)
        oldResponse.send([milk])
        XCTAssertEqual(model.selectedProduct?.id, "bread")
        XCTAssertTrue(model.relatedProducts.isEmpty)
        model.dismissProduct()
        repository.responses[1].send([milk])
        XCTAssertNil(model.selectedProduct)
        XCTAssertTrue(model.relatedProducts.isEmpty)
    }

    func testDetailSnapshotAndStoreScopeSurviveFurtherResults() throws {
        let repository = ControlledRelatedCatalogRepository()
        let model = SearchViewModel(repository: repository)
        model.mode = .faster
        let milk = try XCTUnwrap(model.sections.first { $0.storeID == "perekrestok" }?.products.first { $0.id == "milk" })
        model.showProduct(milk, storeID: "perekrestok")
        let alternatives = SearchMockData.snapshot().relatedItems(to: milk.id)
        repository.responses[0].send(alternatives)
        XCTAssertEqual(model.relatedProducts.count, 2)
        model.mode = .cheaper
        repository.responses[0].send([])
        XCTAssertEqual(model.relatedProducts.count, 2, "A new snapshot cannot invalidate navigation inside the sheet")
        XCTAssertTrue(model.relatedProducts.allSatisfy { $0.offers.count == 1 && $0.offers[0].storeID == "perekrestok" })
        model.dismissProduct()
        XCTAssertEqual(model.relatedProducts.count, 2, "Retain pushed destinations during the dismissal animation")
    }

    func testQueryFiltersBothModesAndClearingRestoresAllShelves() async {
        let model = mockViewModel()
        model.query = "  " + Texts.Search.Mock.milk.uppercased() + "  "
        _ = await publishedItems(model.$items.eraseToAnyPublisher(), where: { $0.count == 3 })
        XCTAssertEqual(model.sections.map(\.id), ["milk"])
        model.mode = .faster
        XCTAssertEqual(model.sections.map { $0.products.count }, [3, 3])
        model.query = "__missing_product__"
        _ = await publishedItems(model.$items.eraseToAnyPublisher(), where: { $0.isEmpty })
        XCTAssertTrue(model.sections.isEmpty)
        model.query = ""
        _ = await publishedItems(model.$items.eraseToAnyPublisher(), where: { $0.count == 18 })
        model.mode = .cheaper
        XCTAssertEqual(model.sections.count, 6)
    }

    func testProductQuantitiesAreSharedWithHomeAndSurviveSearchModeChanges() {
        let selection = ProductSelection()
        let home = HomeViewModel(selection: selection)
        let search = mockViewModel()
        let product = search.sections[0].products[0]
        selection.setQuantity(2, for: product.id)
        XCTAssertEqual(home.quantity(for: product.id), 2)
        search.mode = .faster
        XCTAssertEqual(selection.quantity(for: product.id), 2)
        home.setQuantity(3, for: product.id)
        XCTAssertEqual(selection.quantity(for: product.id), 3)
        selection.setQuantity(1_000, for: product.id)
        XCTAssertEqual(selection.quantity(for: product.id), ProductSelection.quantityRange.upperBound)
        selection.setQuantity(-1, for: product.id)
        XCTAssertNil(selection.quantities[product.id])
    }

    private func mockViewModel() -> SearchViewModel {
        SearchViewModel(repository: MockSearchRepository(), stores: SearchMockData.stores,
                        groupOrder: SearchMockData.groupOrder)
    }

    func testRefreshErrorSurvivesSearchAndClearsOnlyAfterSuccessfulRefresh() async throws {
        let source = ControlledCatalogSource()
        let repository = DefaultCatalogRepository(source: source)
        try await repository.importCatalog(CatalogFixtures.catalog())
        let viewModel = SearchViewModel(repository: repository)
        await viewModel.refresh()
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        viewModel.query = "missing"
        _ = await publishedItems(viewModel.$items.dropFirst().eraseToAnyPublisher(), where: { $0.isEmpty })
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        viewModel.query = "молоко"
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.map(\.id), ["p1"])
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        await source.succeed(with: CatalogFixtures.catalog(price: 120))
        await viewModel.refresh()
        XCTAssertNil(viewModel.refreshErrorMessage)
        let updated = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { $0.first?.offers.first?.offer.price == 120 })
        XCTAssertEqual(updated.first?.offers.first?.offer.price, 120)
    }

    func testCacheFailureAndSourceFailureAreIndependentAndRetryable() async throws {
        let cache = ControlledCatalogCache()
        cache.loadError = URLError(.cannotOpenFile)
        let source = ControlledCatalogSource()
        let repository = DefaultCatalogRepository(cache: cache, source: source)
        let viewModel = SearchViewModel(repository: repository)
        await repository.prepareCache()
        await viewModel.refresh()
        XCTAssertTrue(viewModel.isCacheUnavailable)
        XCTAssertNotNil(viewModel.refreshErrorMessage)
        await source.succeed(with: CatalogFixtures.catalog())
        await viewModel.refresh()
        XCTAssertTrue(viewModel.isCacheUnavailable)
        XCTAssertNil(viewModel.refreshErrorMessage)
        cache.loadError = nil
        await viewModel.retry()
        XCTAssertFalse(viewModel.isCacheUnavailable)
        XCTAssertNil(viewModel.refreshErrorMessage)
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.map(\.id), ["p1"])
    }

    func testFailedCacheWriteKeepsSourceResultsAndShowsOnlyCacheFailure() async throws {
        let cache = ControlledCatalogCache()
        cache.writeError = URLError(.cannotWriteToFile)
        let repository = DefaultCatalogRepository(cache: cache, source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        let viewModel = SearchViewModel(repository: repository)
        await repository.prepareCache()
        let failed = expectation(description: "Cache write failure is shown")
        let observation = viewModel.$isCacheUnavailable.filter { $0 }.prefix(1).sink { _ in failed.fulfill() }
        defer { observation.cancel() }
        await viewModel.refresh()
        await fulfillment(of: [failed], timeout: 5)
        let items = await publishedItems(viewModel.$items.eraseToAnyPublisher(), where: { !$0.isEmpty })
        XCTAssertEqual(items.first?.offers.first?.offer.price, Decimal(string: "99.90"))
        XCTAssertNil(viewModel.refreshErrorMessage)
        XCTAssertTrue(cache.snapshot.products.isEmpty)
    }
}

@MainActor
private final class ControlledRelatedCatalogRepository: CatalogRepository {
    let canRefresh = false
    private let catalog = MockSearchRepository()
    private(set) var responses: [PassthroughSubject<[CatalogItem], Never>] = []

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        catalog.observeProducts(matching: query)
    }

    func observeRelatedProducts(to productID: String, storeID: String?) -> AnyPublisher<[CatalogItem], Never> {
        let response = PassthroughSubject<[CatalogItem], Never>()
        responses.append(response)
        return response.eraseToAnyPublisher()
    }

    func importCatalog(_ batch: CatalogImport) async throws {}
    func refresh() async throws {}
}
