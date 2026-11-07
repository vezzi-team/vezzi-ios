import Combine
import Foundation

/// Preview-only values; never seed these records into the application's store.
@MainActor
final class PreviewCatalogRepository: CatalogRepository {
    let canRefresh = false
    private let snapshot: CatalogSnapshot

    init(snapshot: CatalogSnapshot = CatalogSnapshot()) {
        self.snapshot = snapshot
    }

    nonisolated deinit {}

    func observeProducts(matching query: String) -> AnyPublisher<[CatalogItem], Never> {
        Just(snapshot.items(matching: query))
            .eraseToAnyPublisher()
    }

    func observeRelatedProducts(to productID: String, storeID: String?) -> AnyPublisher<[CatalogItem], Never> {
        Just(snapshot.relatedItems(to: productID, storeID: storeID)).eraseToAnyPublisher()
    }

    func importCatalog(_ batch: CatalogImport) async throws {}
    func refresh() async throws {}

    static var sample: PreviewCatalogRepository {
        let product = CatalogProduct(id: "preview-product", name: "Молоко", brand: "Пример",
                                     packageQuantity: 900, packageUnit: "мл")
        let store = CatalogStore(id: "preview-store", name: "Магазин рядом")
        let offer = CatalogOffer(id: "preview-offer", productID: product.id, storeID: store.id,
                                 price: Decimal(string: "99.90")!, currency: "RUB", inStock: true,
                                 sourceUpdatedAt: Date())
        let batch = CatalogCacheBatch(products: [product], stores: [store],
                                      offers: [StoredCatalogOffer(offer: offer, cachedAt: Date())])
        // These static fixtures must satisfy the same invariants as real catalog data.
        let snapshot = try! CatalogSnapshot().applying(batch).snapshot
        return PreviewCatalogRepository(snapshot: snapshot)
    }
}
