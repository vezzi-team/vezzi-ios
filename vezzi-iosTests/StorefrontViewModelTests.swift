import XCTest
@testable import vezzi_ios

@MainActor
final class StorefrontViewModelTests: XCTestCase {
    func testHomeSharesSelectedOriginAndQuantitiesWithList() {
        let list = ShoppingListRepository()
        let repository = MockSearchRepository()
        let model = StorefrontViewModel(page: .home, repository: repository, list: list)
        let catalog = StorefrontViewModel(page: .catalog, repository: repository, list: list)
        XCTAssertTrue(model.selection === catalog.selection)
        XCTAssertTrue(model.hasProducts)
        XCTAssertFalse(model.shelves.deals.isEmpty)
        XCTAssertFalse(catalog.products.isEmpty)
        list.setRoute(origin: .defaultOrigin, options: .init(), address: "Chosen street")
        XCTAssertEqual(model.list.originAddress, "Chosen street")
        XCTAssertEqual(model.list.origin, .defaultOrigin)
    }

    func testHomeSelectsFiveAvailableFreshPromotionsAndKeepsAllOffersForDetails() throws {
        let types = ["Хлеб", "Молоко", "Макаронные изделия", "Яйца куриные", "Крупы", "Масло сливочное", "Хлеб"]
        let items = types.enumerated().map { index, type in
            let product = CatalogProduct(id: String(index), name: type, productType: type)
            func offer(_ id: String, _ price: Decimal, promo: Bool = true, fresh: Bool = true, stock: Bool? = true) -> CachedOffer {
                let value = CatalogOffer(id: id, productID: product.id, storeID: id, price: price, currency: "RUB",
                                         inStock: stock, priceType: promo ? "promo" : "current")
                return CachedOffer(offer: value, store: CatalogStore(id: id, name: id), cachedAt: Date(), isFresh: fresh)
            }
            return CatalogItem(product: product, offers: [offer("ordinary", 80, promo: false), offer("stale", 40, fresh: false),
                               offer("missing", 30, stock: false), offer("unknown", 20, stock: nil),
                               offer("promo-b", 100), offer("promo-a", 90)])
        }
        let ineligible = items.map { CatalogItem(product: $0.product, offers: Array($0.offers.prefix(4))) }
        XCTAssertTrue(HomeShelves(items: ineligible).deals.isEmpty)
        let shelves = HomeShelves(items: items)
        XCTAssertEqual(shelves.deals.map(\.id), ["0", "1", "2", "3", "4"])
        let deal = try XCTUnwrap(shelves.deals.first)
        XCTAssertEqual(deal.lowestPrice, 90)
        XCTAssertEqual(deal.offers.map(\.id), ["promo-a"])
        XCTAssertEqual(shelves.detailProduct(for: deal).offers.count, 6)
        XCTAssertEqual(shelves.essentials.map(\.id), ["1", "0", "2", "3", "4", "5"])
        XCTAssertTrue(HomeShelves(items: items.map { CatalogItem(product: $0.product, offers: []) }).essentials.isEmpty)
    }

    func testOpeningAnOfferFromTheShelfPreservesItsStoreAndPriceOnlyForThatPresentation() throws {
        var batch = CatalogFixtures.catalog(price: 37)
        batch.stores.append(CatalogStore(id: "promo-store", name: "Promo store"))
        batch.offers.append(CatalogOffer(id: "promo", productID: "p1", storeID: "promo-store", price: 41,
                                         currency: "RUB", inStock: true, priceType: "promo"))
        let repository = PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch))
        let home = StorefrontViewModel(page: .home, repository: repository)
        let card = try XCTUnwrap(home.shelves.deals.first)
        let product = home.shelves.detailProduct(for: card)
        home.showProduct(product, promotion: card.lowestOffer)
        let detail = try XCTUnwrap(home.selectedDetail)
        XCTAssertEqual(detail.promotion?.storeID, "promo-store")
        XCTAssertEqual(detail.promotion?.price, 41)
        XCTAssertEqual(detail.product.lowestPrice, 37)
        XCTAssertEqual(Set(detail.product.offers.map(\.storeID)), ["s1", "promo-store"])

        home.dismissProduct()
        home.showProduct(product)
        XCTAssertNil(home.selectedDetail?.promotion)
        XCTAssertEqual(home.selectedDetail?.product.lowestPrice, 37)
    }

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
        let model = StorefrontViewModel(page: .catalog, repository: PreviewCatalogRepository(snapshot: snapshot))
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
        let home = StorefrontViewModel(page: .catalog, repository: repository)
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
        let model = StorefrontViewModel(page: .catalog, repository: PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch)), list: ShoppingListRepository(selection: selection))
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
        XCTAssertNil(model.selectedDetail)
        XCTAssertEqual(model.relatedProducts.map(\.id), ["other-milk"])
    }

    func testCatalogLoadsBeyondSearchLimitAndClearsRemovedCategory() async throws {
        let repository = DefaultCatalogRepository(source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        var batch = CatalogFixtures.largeCatalog()
        batch.products[0].category = "Old category"
        try await repository.importCatalog(batch)
        let model = StorefrontViewModel(page: .catalog, repository: repository)
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1000 })
        XCTAssertEqual(model.products.count, 1000)
        model.selectedCategory = ProductCategory(rawValue: "Old category")
        await model.refresh()
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1 })
        XCTAssertNil(model.selectedCategory)
        XCTAssertEqual(model.products.map(\.id), ["p1"])
    }
}
