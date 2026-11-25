import Foundation

/// Shared records returned by both catalog exports and account-owned carts/plans.
nonisolated struct CatalogProductDTO: Decodable, Sendable {
    let id: Int64
    let name: String
    let brand: String?
    let category: String
    let productType: String?
    let packageAmount: Decimal
    let packageUnit: String
    let imageUrl: String?
    let imageWideUrl: String?

    var record: CatalogProduct {
        CatalogProduct(id: String(id), name: name, brand: brand, category: category,
                       productType: productType, packageQuantity: packageAmount, packageUnit: packageUnit,
                       imageURL: mediaURL(imageUrl), wideImageURL: mediaURL(imageWideUrl))
    }
}

nonisolated struct CatalogStoreDTO: Decodable, Sendable {
    let id: Int64
    let chain: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let format: String
    let logoUrl: String?

    var record: CatalogStore {
        CatalogStore(id: String(id), name: name, chainName: chain, address: address,
                     latitude: latitude, longitude: longitude, format: format, logoURL: mediaURL(logoUrl))
    }
}

nonisolated private func mediaURL(_ value: String?) -> URL? {
    guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
          let host = url.host, !host.isEmpty else { return nil }
    return url
}
