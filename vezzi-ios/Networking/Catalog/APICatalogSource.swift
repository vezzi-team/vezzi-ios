import Foundation

/// Decodes the server's complete, versioned catalog away from the main actor.
nonisolated struct APICatalogSource: CatalogSource {
    let client: any AuthorizedRequestPerforming

    @concurrent func loadCatalog(ifNoneMatch: String?) async throws -> CatalogSourceResult {
        let headers = ifNoneMatch.map { ["If-None-Match": $0] } ?? [:]
        let response = try await client.authorizedResponse(for: APIRequest(path: "catalog/export", headers: headers))
        try Task.checkCancellation()
        if response.status == 304 {
            guard ifNoneMatch != nil else { throw APIError.invalidResponse }
            return .notModified
        }
        guard response.status == 200 else { throw APIError.invalidResponse }
        let export: Export = try response.decode()
        let receivedAt = Date()
        let batch = CatalogImport(
            products: export.products.map(\.record),
            stores: export.stores.map(\.record),
            offers: export.offers.map {
                CatalogOffer(id: $0.id, productID: String($0.productId), storeID: String($0.storeId),
                             price: Decimal($0.priceKopecks) / 100, currency: $0.currency ?? "RUB", inStock: $0.inStock,
                             sourceUpdatedAt: $0.sourceUpdatedAt, sourceProductID: $0.sourceProductId,
                             sourceURL: $0.sourceUrl.flatMap(URL.init(string:)), priceType: $0.priceType,
                             cardPrice: $0.cardPriceKopecks.map { Decimal($0) / 100 }, priceConditions: $0.priceConditions)
            })
        var cached = CatalogCacheBatch(import: batch, cachedAt: receivedAt)
        cached.metadata = CatalogMetadata(importID: export.importId, importedAt: export.importedAt,
                                          isSynthetic: export.isSynthetic, offerMaxAgeHours: export.offerMaxAgeHours,
                                          etag: response.etag, validatedAt: receivedAt)
        cached.replacesCatalog = true
        // Validate both values and references before the repository publishes anything.
        _ = try CatalogSnapshot().applying(cached)
        return .snapshot(cached)
    }

    private struct Export: Decodable, Sendable {
        let importId: Int64
        let importedAt: Date
        let isSynthetic: Bool
        let offerMaxAgeHours: Int
        let products: [CatalogProductDTO]
        let stores: [CatalogStoreDTO]
        let offers: [OfferDTO]
    }

    private struct OfferDTO: Decodable, Sendable {
        let id: String
        let productId: Int64
        let storeId: Int64
        let priceKopecks: Int64
        let currency: String?
        let cardPriceKopecks: Int64?
        let inStock: Bool?
        let priceType: String?
        let priceConditions: String?
        let sourceProductId: String?
        let sourceUrl: String?
        let sourceUpdatedAt: Date
    }
}
