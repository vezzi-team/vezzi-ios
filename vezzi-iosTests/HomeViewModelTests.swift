import XCTest
@testable import vezzi_ios

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testMainPricePrioritizesAvailabilityAndFreshnessAcrossStores() {
        var product = Product(id: "p", name: "Milk", brand: "", packageQuantity: nil, packageUnit: nil, category: nil, offers: [
            ProductOffer(id: "unavailable", storeID: "s1", name: "Store 1", price: 20, inStock: false),
            ProductOffer(id: "stale", storeID: "s2", name: "Store 2", price: 50, isFresh: false),
            ProductOffer(id: "fresh-b", storeID: "s3", name: "Store 3", price: 100),
            ProductOffer(id: "fresh-a", storeID: "s4", name: "Store 4", price: 100, inStock: nil)
        ])
        XCTAssertEqual(product.lowestOffer?.id, "fresh-a")
        product.offers.removeAll { $0.id.hasPrefix("fresh-") }
        XCTAssertEqual(product.lowestOffer?.id, "stale")
        XCTAssertEqual(product.lowestPrice, 50)
        XCTAssertEqual(product.lowestOffer?.isFresh, false)
        product.offers.removeAll { $0.inStock != false }
        XCTAssertEqual(product.lowestOffer?.id, "unavailable", "Retain a fallback price when every store is out of stock")
        product.offers = []
        XCTAssertNil(product.lowestOffer)
    }

    func testCatalogPresentationSeparatesBrandAndStoreAddress() throws {
        let name = "Молоко «Простоквашино» 2,5%"
        let address = "Санкт-Петербург, Лесная улица, 10"
        let storeName = "Пятёрочка — " + address
        let batch = CatalogImport(
            products: [CatalogProduct(id: "milk", name: name, brand: "Простоквашино", packageQuantity: 930, packageUnit: "ml")],
            stores: [CatalogStore(id: "store", name: storeName, address: address)],
            offers: [CatalogOffer(id: "offer", productID: "milk", storeID: "store", price: 90, currency: "RUB")])
        let snapshot = try CatalogFixtures.snapshot(batch)
        let model = HomeViewModel(repository: PreviewCatalogRepository(snapshot: snapshot))
        let product = try XCTUnwrap(model.products.first)
        let offer = try XCTUnwrap(product.offers.first)
        XCTAssertEqual(product.displayName, "Молоко 2,5%")
        XCTAssertEqual(product.brand, "Простоквашино")
        XCTAssertEqual(product.packageQuantity, 930)
        XCTAssertEqual(offer.storeTitle, "Пятёрочка")
        XCTAssertEqual(offer.address, address)
        XCTAssertEqual(offer.displayAddress, "Лесная улица, 10")
        XCTAssertEqual(product.name, name)
        XCTAssertEqual(offer.name, storeName)
        XCTAssertEqual(snapshot.products["milk"]?.name, name)
    }

    func testSeparateBrandLabelPreservesMeaningfulProductNames() {
        let cases = [
            ("Prostokvashino Milk", "prostokvashino", "Milk"),
            ("Молоко Домик в деревне 3,5%", "Домик в деревне", "Молоко 3,5%"),
            ("Молоко A+B", "A+B", "Молоко"),
            ("Молоко Агроферма", "Ферма", "Молоко Агроферма"),
            ("Молоко", " ", "Молоко"),
            ("Простоквашино", "Простоквашино", "Простоквашино")
        ]
        for (name, brand, expected) in cases {
            let product = Product(id: "p", name: name, brand: brand, packageQuantity: nil,
                                  packageUnit: nil, category: nil, offers: [])
            XCTAssertEqual(product.displayName, expected)
        }
        let offer = ProductOffer(id: "o", storeID: "s", name: "Магазин № 10", price: 90)
        XCTAssertEqual(offer.storeTitle, "Магазин № 10")
    }

    func testStoreTitleUsesChainWhenNameAndAddressHaveDifferentFormats() throws {
        let name = "METRO — Комендантский проспект, 3 лит А"
        let address = "Санкт-Петербург, Комендантский проспект, 3 лит А"
        let batch = CatalogImport(
            products: [CatalogProduct(id: "p", name: "Картофель фри")],
            stores: [CatalogStore(id: "s", name: name, chainName: " METRO ", address: address)],
            offers: [CatalogOffer(id: "o", productID: "p", storeID: "s", price: 124, currency: "RUB")])
        let repository = PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch))
        let home = HomeViewModel(repository: repository)
        let search = SearchViewModel(repository: repository)
        for offer in [home.products.first?.offers.first, search.sections.first?.products.first?.offers.first] {
            let offer = try XCTUnwrap(offer)
            XCTAssertEqual(offer.storeTitle, "METRO")
            XCTAssertEqual(offer.name, name)
            XCTAssertEqual(offer.address, address)
            XCTAssertEqual(offer.displayAddress, "Комендантский проспект, 3 лит А")
            XCTAssertEqual(offer.storeID, "s")
        }
        let fallback = ProductOffer(id: "o", storeID: "s", name: "Магазин — Лесная, 1", price: 90,
                                    address: "Лесная, 1", chainName: " ")
        XCTAssertEqual(fallback.storeTitle, "Магазин")
    }

    func testRepositoryCategoriesAndFilteringPreserveSharedQuantities() throws {
        let batch = CatalogImport(products: [
            CatalogProduct(id: "milk", name: "Milk", category: "Dairy", productType: "milk"),
            CatalogProduct(id: "other-milk", name: "Other milk", category: "Dairy", productType: "milk"),
            CatalogProduct(id: "apples", name: "Apples", category: "Produce")
        ])
        let selection = ProductSelection()
        let model = HomeViewModel(repository: PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch)), selection: selection)
        XCTAssertEqual(model.categories.map(\.rawValue), ["Dairy", "Produce"])
        model.setQuantity(2, for: "milk")
        model.selectedCategory = ProductCategory(rawValue: "Produce")
        XCTAssertEqual(model.filteredProducts.map(\.id), ["apples"])
        selection.setQuantity(3, for: "milk")
        model.selectedCategory = nil
        XCTAssertEqual(model.filteredProducts.count, 3)
        XCTAssertEqual(model.quantity(for: "milk"), 3)
        model.showProduct(try XCTUnwrap(model.products.first { $0.id == "milk" }))
        XCTAssertEqual(model.relatedProducts.map(\.id), ["other-milk"])
        model.dismissProduct()
        XCTAssertNil(model.selectedProduct)
        XCTAssertEqual(model.relatedProducts.map(\.id), ["other-milk"])
    }

    func testHomeLoadsBeyondSearchLimitAndClearsRemovedCategory() async throws {
        let repository = DefaultCatalogRepository(source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        var batch = CatalogFixtures.largeCatalog()
        batch.products[0].category = "Old category"
        try await repository.importCatalog(batch)
        let model = HomeViewModel(repository: repository)
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1000 })
        XCTAssertEqual(model.products.count, 1000)
        model.selectedCategory = ProductCategory(rawValue: "Old category")
        await model.refresh()
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1 })
        XCTAssertNil(model.selectedCategory)
        XCTAssertEqual(model.products.map(\.id), ["p1"])
    }
}
