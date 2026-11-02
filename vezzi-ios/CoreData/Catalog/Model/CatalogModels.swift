import Foundation

nonisolated enum CatalogSearch {
    static let resultLimit = 50
}

// Value types can cross queues; Core Data objects never leave the storage layer.
nonisolated struct CatalogProduct: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var brand: String?
    var category: String?
    var productType: String?
    var packageQuantity: Decimal?
    var packageUnit: String?
}

nonisolated struct CatalogStore: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var chainName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var isActive: Bool = true
}

nonisolated struct CatalogOffer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let productID: String
    let storeID: String
    var price: Decimal
    var currency: String
    var inStock: Bool?
    var sourceUpdatedAt: Date?
    var sourceID: String?
    var sourceProductID: String?
    var sourceURL: URL?
    var matchStatus: String?
    var dataOrigin: String?
    var priceType: String?

    func canReplace(sourceDate: Date?) -> Bool {
        guard let sourceDate else { return true }
        return sourceUpdatedAt.map { $0 >= sourceDate } ?? false
    }
}

/// An upsert batch. Missing records are retained, never interpreted as deletions.
nonisolated struct CatalogImport: Codable, Sendable {
    var products: [CatalogProduct] = []
    var stores: [CatalogStore] = []
    var offers: [CatalogOffer] = []
}

/// Cache metadata belongs to the received record, not to a later disk write.
nonisolated struct StoredCatalogOffer: Equatable, Identifiable, Sendable {
    var id: String { offer.id }
    let offer: CatalogOffer
    let cachedAt: Date
}

nonisolated struct CatalogCacheBatch: Sendable {
    var products: [CatalogProduct] = []
    var stores: [CatalogStore] = []
    var offers: [StoredCatalogOffer] = []

    init(products: [CatalogProduct] = [], stores: [CatalogStore] = [], offers: [StoredCatalogOffer] = []) {
        self.products = products
        self.stores = stores
        self.offers = offers
    }

    init(import batch: CatalogImport, cachedAt: Date) {
        products = batch.products
        stores = batch.stores
        offers = batch.offers.map { StoredCatalogOffer(offer: $0, cachedAt: cachedAt) }
    }

    var values: CatalogImport {
        CatalogImport(products: products, stores: stores, offers: offers.map(\.offer))
    }

    func validate() throws {
        try CatalogImportValidator.validate(values)
        for record in offers where !record.cachedAt.timeIntervalSince1970.isFinite {
            throw CatalogError.invalidRecord(entity: "Offer", id: record.id)
        }
    }
}

/// Pending writes retain IDs only; their latest values are read when the writer is ready.
nonisolated struct CatalogRecordIDs: Sendable {
    var products: Set<String> = []
    var stores: Set<String> = []
    var offers: Set<String> = []

    var isEmpty: Bool { products.isEmpty && stores.isEmpty && offers.isEmpty }

    mutating func formUnion(_ other: CatalogRecordIDs) {
        products.formUnion(other.products)
        stores.formUnion(other.stores)
        offers.formUnion(other.offers)
    }
}

nonisolated struct CachedOffer: Equatable, Identifiable, Sendable {
    var id: String { offer.id }
    let offer: CatalogOffer
    let store: CatalogStore
    let cachedAt: Date
}

nonisolated struct CatalogItem: Equatable, Identifiable, Sendable {
    var id: String { product.id }
    let product: CatalogProduct
    let offers: [CachedOffer]
}
