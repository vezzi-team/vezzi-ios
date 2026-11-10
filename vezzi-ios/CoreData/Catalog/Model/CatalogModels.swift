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

    /// Shared by catalog grouping and the independent alternatives query.
    var groupID: String { productType ?? category ?? id }
}

nonisolated struct CatalogStore: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var chainName: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var isActive: Bool = true
    var format: String?
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
    var cardPrice: Decimal?
    var priceConditions: String?

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
    var metadata: CatalogMetadata?
    var replacesCatalog = false

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
        if let metadata { try metadata.validate() }
    }
}

/// Stored atomically with the snapshot it describes; receipt time is not price freshness.
nonisolated struct CatalogMetadata: Equatable, Sendable {
    let importID: Int64
    let importedAt: Date
    let isSynthetic: Bool
    let offerMaxAgeHours: Int
    var etag: String?
    var validatedAt: Date

    func validate() throws {
        guard importID > 0, offerMaxAgeHours > 0,
              importedAt.timeIntervalSince1970.isFinite, validatedAt.timeIntervalSince1970.isFinite else {
            throw CatalogError.invalidRecord(entity: "Catalog", id: String(importID))
        }
    }
}

nonisolated enum CatalogSourceResult: Sendable {
    case snapshot(CatalogCacheBatch)
    case notModified
}

nonisolated struct CatalogStatus: Equatable, Sendable {
    var isRefreshing = false
    var hasSnapshot = false
    var isSynthetic = false
    var isOffline = false
    var failure: CatalogRefreshFailure?
    var validatedAt: Date?
}

nonisolated enum CatalogRefreshFailure: Equatable, Sendable {
    case offline
    case authenticationRequired
    case unavailable

    static func from(_ error: Error) -> Self {
        if let failure = error as? AuthenticationFailure {
            if failure.invalidatesSession { return .authenticationRequired }
            if failure == .offline { return .offline }
        }
        if (error as? APIError)?.status == 401 { return .authenticationRequired }
        if let error = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(error.code) {
            return .offline
        }
        return .unavailable
    }
}

/// Pending writes retain IDs only; their latest values are read when the writer is ready.
nonisolated struct CatalogRecordIDs: Sendable {
    var products: Set<String> = []
    var stores: Set<String> = []
    var offers: Set<String> = []
    var metadata = false

    var isEmpty: Bool { products.isEmpty && stores.isEmpty && offers.isEmpty && !metadata }

    mutating func formUnion(_ other: CatalogRecordIDs) {
        products.formUnion(other.products)
        stores.formUnion(other.stores)
        offers.formUnion(other.offers)
        metadata = metadata || other.metadata
    }
}

nonisolated struct CachedOffer: Equatable, Identifiable, Sendable {
    var id: String { offer.id }
    let offer: CatalogOffer
    let store: CatalogStore
    let cachedAt: Date
    var isFresh = true
}

nonisolated struct CatalogItem: Equatable, Identifiable, Sendable {
    var id: String { product.id }
    let product: CatalogProduct
    let offers: [CachedOffer]
}
