import XCTest
@testable import vezzi_ios

@MainActor
final class StorefrontViewModelTests: XCTestCase {
    func testMotiCollectionsKeepAvailableThemedProductsAndStableIDsWhenPricesChange() throws {
        let types = ["Макаронные изделия", "Снеки и чипсы", "Овощи"]
        var batch = CatalogFixtures.catalog()
        batch.products = (0..<30).map { index in
            CatalogProduct(id: String(index), name: "Item \(index)", productType: types[index % types.count])
        }
        batch.offers = batch.products.map { product in
            CatalogOffer(id: product.id, productID: product.id, storeID: "s1", price: 20, currency: "RUB", inStock: product.id != "0")
        }
        let items = try CatalogFixtures.snapshot(batch).allItems()
        for index in batch.offers.indices { batch.offers[index].price = 30 }
        let refreshed = try CatalogFixtures.snapshot(batch).allItems()
        for (collection, count, type) in [(MotiCollection.pasta, 5, types[0]), (.movies, 6, types[1]), (.salad, 4, types[2])] {
            let ids = collection.products(from: items).map(\.id)
            XCTAssertEqual(Set(ids).count, count)
            XCTAssertTrue(ids.allSatisfy { id in id != "0" && batch.products.contains { $0.id == id && $0.productType == type } })

            let products = collection.products(from: refreshed.reversed())
            XCTAssertEqual(products.map(\.id), ids)
            XCTAssertTrue(products.allSatisfy { $0.lowestPrice == 30 })
        }
        let oneItem = items.filter { $0.id == "1" }
        XCTAssertEqual(MotiCollection.salad.products(from: oneItem).map(\.id), ["1"])
        XCTAssertTrue(MotiCollection.movies.products(from: []).isEmpty)
    }

    func testHomeSharesSelectedOriginAndQuantitiesWithList() {
        let list = ShoppingListRepository()
        let repository = MockSearchRepository()
        let model = StorefrontViewModel(page: .home, repository: repository, list: list)
        let catalog = StorefrontViewModel(page: .catalog, repository: repository, list: list)
        XCTAssertTrue(model.selection === catalog.selection)
        XCTAssertTrue(model.hasProducts)
        XCTAssertFalse(model.shelves.deals.isEmpty)
        XCTAssertFalse(catalog.catalogSections.isEmpty)
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
            return CatalogItem(product: product, offers: [offer("ordinary", 95, promo: false), offer("stale", 140, fresh: false),
                               offer("missing", 130, stock: false), offer("unknown", 120, stock: nil),
                               offer("promo-b", 100), offer("promo-a", 90)])
        }
        let ineligible = items.map { CatalogItem(product: $0.product, offers: Array($0.offers.prefix(4))) }
        XCTAssertTrue(HomeShelves(items: ineligible).deals.isEmpty)
        let shelves = HomeShelves(items: items)
        XCTAssertEqual(shelves.deals.map(\.id), ["0", "1", "2", "3", "4"])
        let deal = try XCTUnwrap(shelves.deals.first)
        XCTAssertEqual(deal.promotion?.offer.price, 90)
        XCTAssertEqual(deal.promotion?.offer.id, "promo-a")
        XCTAssertEqual(deal.promotion?.comparisonPrice, 100)
        XCTAssertEqual(deal.offers.count, 6)
        XCTAssertEqual(shelves.essentials.map(\.id), ["1", "0", "2", "3", "4", "5"])
        XCTAssertTrue(HomeShelves(items: items.map { CatalogItem(product: $0.product, offers: []) }).essentials.isEmpty)
    }

    func testDealsShelfRejectsAPromotionWhenAnyStoreShowsALowerPrice() throws {
        let crackers = CatalogProduct(id: "crackers", name: "3 корочки")
        let metro = CatalogStore(id: "metro", name: "METRO")
        let vkusvill = CatalogStore(id: "vkusvill", name: "ВкусВилл")
        let other = CatalogStore(id: "other", name: "Дары природы")

        func deals(cheaperAt store: CatalogStore, priceType: String = "current") throws -> [Product] {
            let batch = CatalogImport(products: [crackers], stores: [metro, vkusvill, other], offers: [
                CatalogOffer(id: "lowest", productID: crackers.id, storeID: store.id, price: 37,
                             currency: "RUB", inStock: true, priceType: priceType),
                CatalogOffer(id: "promo", productID: crackers.id, storeID: vkusvill.id, price: 41,
                             currency: "RUB", inStock: true, priceType: "promo"),
                CatalogOffer(id: "highest", productID: crackers.id, storeID: other.id, price: 48.20,
                             currency: "RUB", inStock: true)
            ])
            return HomeShelves(items: try CatalogFixtures.snapshot(batch).allItems()).deals
        }

        XCTAssertTrue(try deals(cheaperAt: metro).isEmpty)
        XCTAssertTrue(try deals(cheaperAt: vkusvill).isEmpty)
        let promotion = try XCTUnwrap(deals(cheaperAt: metro, priceType: "promo").first?.promotion)
        XCTAssertEqual(promotion.offer.id, "lowest")
        XCTAssertEqual(promotion.offer.price, 37)
        XCTAssertEqual(promotion.comparisonPrice, 48.20)
    }

    func testOpeningATiedLowestPromotionPreservesItsStoreAndPriceOnlyForThatPresentation() throws {
        var batch = CatalogFixtures.catalog(price: 41)
        batch.stores.append(CatalogStore(id: "promo-store", name: "Promo store"))
        batch.offers.append(CatalogOffer(id: "promo", productID: "p1", storeID: "promo-store", price: 41,
                                         currency: "RUB", inStock: true, priceType: "promo"))
        batch.stores.append(CatalogStore(id: "highest", name: "Other store"))
        batch.offers.append(CatalogOffer(id: "highest", productID: "p1", storeID: "highest", price: 50, currency: "RUB", inStock: true))
        let repository = PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch))
        let home = StorefrontViewModel(page: .home, repository: repository)
        let product = try XCTUnwrap(home.shelves.deals.first)
        home.showProduct(product, promotion: product.promotion?.offer)
        let detail = try XCTUnwrap(home.selectedDetail)
        XCTAssertEqual(detail.promotion?.storeID, "promo-store")
        XCTAssertEqual(detail.promotion?.price, 41)
        XCTAssertEqual(detail.product.lowestPrice, 41)
        XCTAssertEqual(Set(detail.product.offers.map(\.storeID)), ["s1", "promo-store", "highest"])

        home.dismissProduct()
        home.showProduct(product)
        XCTAssertNil(home.selectedDetail?.promotion)
        XCTAssertEqual(home.selectedDetail?.product.lowestPrice, 41)
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

    func testDiscountComparesOnlyWithAnotherAvailableStoreInTheSameCurrency() {
        let promo = shelfOffer("promo", storeID: "a", price: 80, isPromo: true, cardPrice: 60)
        let excluded = [
            promo,
            shelfOffer("other-offer", storeID: "a", price: 200),
            shelfOffer("old", price: 200, isFresh: false),
            shelfOffer("missing", price: 200, inStock: false),
            shelfOffer("unknown", price: 200, inStock: nil),
            shelfOffer("foreign", price: 10, currency: "USD"),
            shelfOffer("equal", price: 80)
        ]
        XCTAssertNil(shelfPromotion(for: excluded))
        let stores = excluded + [shelfOffer("near", price: 90), shelfOffer("far", price: 100, cardPrice: 85)]
        let comparison = shelfPromotion(for: stores)
        XCTAssertEqual(comparison?.comparisonPrice, 100)
        XCTAssertEqual(comparison?.savingsFraction, Decimal(string: "0.2"))
        for cheaper in [
            shelfOffer("old-low", price: 70, isFresh: false),
            shelfOffer("unknown-low", price: 70, inStock: nil),
            shelfOffer("missing-low", price: 70, inStock: false)
        ] {
            XCTAssertNil(shelfPromotion(for: stores + [cheaper]), cheaper.id)
        }
    }

    func testDealsShelfKeepsTheLowestQualifyingPromotionAcrossCurrenciesAndBreaksTiesByID() {
        let rubles = [
            shelfOffer("promo-b", price: 41, isPromo: true),
            shelfOffer("promo-a", storeID: "a", price: 41, isPromo: true),
            shelfOffer("ordinary", storeID: "a", price: 41),
            shelfOffer("highest", price: 50)
        ]
        let dollars = [shelfOffer("usd-promo", price: 2, currency: "USD", isPromo: true)]
        let withoutComparison = rubles + dollars
        for offers in [withoutComparison, Array(withoutComparison.reversed())] {
            let promotion = shelfPromotion(for: offers)
            XCTAssertEqual(promotion?.offer.id, "promo-a")
            XCTAssertEqual(promotion?.comparisonPrice, 50)
        }
        let withComparison = withoutComparison + [shelfOffer("usd-highest", price: 3, currency: "USD")]
        let promotion = shelfPromotion(for: withComparison)
        XCTAssertEqual(promotion?.offer.id, "usd-promo")
        XCTAssertEqual(promotion?.comparisonPrice, 3)
    }

    private func shelfPromotion(for offers: [CachedOffer]) -> ProductPromotion? {
        Product(deal: CatalogItem(product: CatalogProduct(id: "p", name: "Item"), offers: offers))?.promotion
    }

    private func shelfOffer(_ id: String, storeID: String? = nil, price: Decimal, currency: String = "RUB",
                            inStock: Bool? = true, isFresh: Bool = true, isPromo: Bool = false,
                            cardPrice: Decimal? = nil) -> CachedOffer {
        let store = CatalogStore(id: storeID ?? id, name: id)
        let offer = CatalogOffer(id: id, productID: "p", storeID: store.id, price: price, currency: currency,
                                 inStock: inStock, priceType: isPromo ? "promo" : "current", cardPrice: cardPrice)
        return CachedOffer(offer: offer, store: store, cachedAt: CatalogFixtures.cachedAt, isFresh: isFresh)
    }

    func testPromotionsAreExclusiveToTheHomeDealsShelf() throws {
        var batch = CatalogFixtures.catalog(price: 100)
        batch.products.append(CatalogProduct(id: "other", name: "Other"))
        batch.stores.append(CatalogStore(id: "s2", name: "Promo store"))
        batch.offers.append(CatalogOffer(id: "promo", productID: "p1", storeID: "s2", price: 80,
                                         currency: "RUB", inStock: true, priceType: "promo"))
        batch.offers.append(CatalogOffer(id: "single", productID: "other", storeID: "s1", price: 50,
                                         currency: "RUB", inStock: true, priceType: "promo"))
        let repository = PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(batch))
        let home = StorefrontViewModel(page: .home, repository: repository)
        XCTAssertEqual(home.shelves.deals.map(\.id), ["p1"])
        XCTAssertEqual(home.shelves.deals.first?.promotion?.comparisonPrice, 100)

        let catalog = StorefrontViewModel(page: .catalog, repository: repository)
        let previews = catalog.catalogSections.flatMap(\.preview)
        XCTAssertEqual(Set(previews.map(\.id)), ["p1", "other"])
        XCTAssertTrue(previews.allSatisfy { $0.promotion == nil })
        let product = try XCTUnwrap(previews.first { $0.id == "p1" })
        XCTAssertEqual(product.lowestPrice, 80)
        catalog.showProduct(product)
        let detail = try XCTUnwrap(catalog.selectedDetail)
        XCTAssertNil(detail.promotion)
        XCTAssertEqual(detail.product.offers.count, 2)
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
        let product = try XCTUnwrap(model.catalogSections.first?.preview.first)
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
        let catalog = StorefrontViewModel(page: .catalog, repository: repository)
        let search = SearchViewModel(repository: repository)
        for offer in [catalog.catalogSections.first?.preview.first?.offers.first, search.sections.first?.products.first?.offers.first] {
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

    func testCatalogSectionsAndFullCategoryUseTheSameOrderAndSharedSelection() throws {
        var products = (0..<7).map { CatalogProduct(id: "milk-\($0)", name: "Milk \($0)", category: " Dairy ", productType: "milk") }
        products.append(contentsOf: [
            CatalogProduct(id: "fruit", name: "Apple", category: "Produce"),
            CatalogProduct(id: "extra", name: "Extra", category: "Accessories"),
            CatalogProduct(id: "unknown", name: "Unknown", category: "  "),
            CatalogProduct(id: "missing", name: "Missing")
        ])
        let repo = PreviewCatalogRepository(snapshot: try CatalogFixtures.snapshot(CatalogImport(products: products)))
        let list = ShoppingListRepository()
        let model = StorefrontViewModel(page: .catalog, repository: repo, list: list)
        let sections = model.catalogSections
        XCTAssertEqual(sections.map(\.id.rawValue), ["Dairy", "Produce", "Accessories", ""])
        let dairy = try XCTUnwrap(sections.first)
        let full = StorefrontViewModel(page: .collection(.category(dairy.id)), repository: repo, list: list)
        XCTAssertEqual(full.products.count, 7)
        XCTAssertEqual(dairy.preview.map(\.id), Array(full.products.prefix(4)).map(\.id))
        XCTAssertEqual(Set(sections.last!.preview.map(\.id)), ["unknown", "missing"])
        let milk = try XCTUnwrap(full.products.last)
        full.selection.setQuantity(2, for: milk.id)
        XCTAssertEqual(model.selection.quantity(for: milk.id), 2)
        full.showProduct(milk)
        XCTAssertEqual(full.selectedDetail?.product.id, milk.id)
        XCTAssertFalse(full.relatedProducts.isEmpty)
        full.dismissProduct()
        XCTAssertNil(full.selectedDetail)
    }

    func testCatalogAndOpenCategoryFollowFullSnapshotReplacement() async throws {
        let repository = DefaultCatalogRepository(source: FixedCatalogSource(batch: CatalogFixtures.catalog()))
        var batch = CatalogFixtures.largeCatalog()
        for index in batch.products.indices { batch.products[index].category = "Old category" }
        try await repository.importCatalog(batch)
        let overview = StorefrontViewModel(page: .catalog, repository: repository)
        let category = StorefrontViewModel(page: .collection(.category(.init(rawValue: "Old category"))), repository: repository)
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1000 })
        XCTAssertEqual(overview.catalogSections.first?.preview.count, 4)
        XCTAssertEqual(category.products.count, 1000)
        await overview.refresh()
        _ = await publishedItems(repository.observeAllProducts(), where: { $0.count == 1 })
        XCTAssertEqual(overview.catalogSections.map(\.id), [.uncategorized])
        XCTAssertEqual(overview.catalogSections.first?.preview.map(\.id), ["p1"])
        XCTAssertTrue(category.products.isEmpty)
    }
}
