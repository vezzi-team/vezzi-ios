import Combine
import Foundation

/// Explicitly injected fixtures. They never enter the persistent catalog.
enum SearchMockData {
    static let stores = [
        "pyaterochka": SearchStoreInfo(walkingMinutes: 5, distance: Measurement(value: 350, unit: .meters)),
        "perekrestok": SearchStoreInfo(walkingMinutes: 15, distance: Measurement(value: 1, unit: .kilometers))
    ]

    static let groupOrder = ProductMockData.products.map(\.id)

    static func snapshot() -> CatalogSnapshot {
        let storeRecords = [
            CatalogStore(id: "pyaterochka", name: Texts.Product.Mock.pyaterochka),
            CatalogStore(id: "perekrestok", name: Texts.Search.Mock.perekrestok)
        ]
        let groupTitles = [Texts.Search.Mock.milk, Texts.Search.Mock.bread, Texts.Product.Mock.apples,
                           Texts.Product.Mock.eggs, Texts.Product.Mock.pasta, Texts.Product.Mock.tomatoes]
        var batch = CatalogImport(stores: storeRecords)
        for (group, title) in zip(ProductMockData.productGroups, groupTitles) {
            guard let groupID = group.first?.id else { continue }
            for product in group {
                batch.products.append(CatalogProduct(id: product.id, name: product.name, brand: product.brand,
                                                     category: title, productType: groupID,
                                                     packageQuantity: product.packageQuantity, packageUnit: product.packageUnit))
                for (store, offer) in zip(storeRecords, product.offers) {
                    batch.offers.append(CatalogOffer(id: product.id + "." + store.id, productID: product.id,
                                                     storeID: store.id, price: offer.price, currency: offer.currency,
                                                     inStock: true))
                }
            }
        }
        // Static fixtures are checked by the same validator as imported catalog records.
        return try! CatalogSnapshot().applying(CatalogCacheBatch(import: batch, cachedAt: Date())).snapshot
    }
}

@MainActor
final class MockSearchRepository: CatalogRepository {
    let canRefresh = false
    private let snapshot = SearchMockData.snapshot()

    nonisolated deinit {}

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        Just(snapshot.items(matching: query)).eraseToAnyPublisher()
    }

    func observeRelatedProducts(to productID: String, storeID: String?) -> AnyPublisher<[CatalogItem], Never> {
        Just(snapshot.relatedItems(to: productID, storeID: storeID)).eraseToAnyPublisher()
    }

    func importCatalog(_ batch: CatalogImport) async throws {}
    func refresh() async throws {}
}
