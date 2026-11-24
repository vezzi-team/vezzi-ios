import Combine
import Foundation

/// One snapshot per visited product for the lifetime of its detail sheet.
@MainActor
final class ProductDetailViewModel: ObservableObject {
    @Published private var analogIDs: [String: [String]] = [:]
    private(set) var productsByID: [String: Product] = [:]

    nonisolated deinit {}

    func alternatives(for productID: String) -> [Product] {
        (analogIDs[productID] ?? []).compactMap { productsByID[$0] }
    }

    func loadAlternatives(for productID: String, using load: (String) async -> [Product]) async {
        guard analogIDs[productID] == nil else { return }
        let products = await load(productID)
        guard !Task.isCancelled else { return }
        for product in products where productsByID[product.id] == nil {
            productsByID[product.id] = product
        }
        analogIDs[productID] = products.map(\.id)
    }
}

extension CatalogRepository {
    func alternativeProducts(for productID: String, storeID: String? = nil,
                             distances: [String: Measurement<UnitLength>] = [:],
                             localOrder: ((Product, Product) -> Bool)? = nil) async -> [Product] {
        let results = await observeRelatedProducts(to: productID, storeID: storeID)
        var iterator = results.values.makeAsyncIterator()
        guard !Task.isCancelled, let alternatives = await iterator.next() else { return [] }
        let products = alternatives.items.map { Product(catalog: $0, distances: distances) }
        if case .local = alternatives, let localOrder { return products.sorted(by: localOrder) }
        return products
    }
}
