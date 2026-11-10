import Foundation

nonisolated enum CatalogImportValidator {
    static func validate(_ batch: CatalogImport) throws {
        try validateIDs(batch.products.map(\.id), entity: "Product")
        try validateIDs(batch.stores.map(\.id), entity: "Store")
        try validateIDs(batch.offers.map(\.id), entity: "Offer")

        for product in batch.products {
            let hasQuantity = product.packageQuantity != nil
            let hasUnit = product.packageUnit.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
            guard !product.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  hasQuantity == hasUnit,
                  product.packageQuantity.map({ !$0.isNaN && $0 > 0 }) ?? true else {
                throw CatalogError.invalidRecord(entity: "Product", id: product.id)
            }
        }
        for store in batch.stores {
            guard !store.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (store.latitude == nil) == (store.longitude == nil),
                  store.latitude.map({ $0.isFinite && (-90...90).contains($0) }) ?? true,
                  store.longitude.map({ $0.isFinite && (-180...180).contains($0) }) ?? true else {
                throw CatalogError.invalidRecord(entity: "Store", id: store.id)
            }
        }
        for offer in batch.offers {
            guard !offer.price.isNaN, offer.price >= 0,
                  offer.cardPrice.map({ !$0.isNaN && $0 >= 0 }) ?? true,
                  offer.currency.utf8.count == 3,
                  offer.currency.utf8.allSatisfy({ (65...90).contains($0) }),
                  offer.sourceUpdatedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
                throw CatalogError.invalidRecord(entity: "Offer", id: offer.id)
            }
        }
    }

    private static func validateIDs(_ ids: [String], entity: String) throws {
        var seen = Set<String>()
        for id in ids {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.invalidRecord(entity: entity, id: id)
            }
            guard seen.insert(id).inserted else {
                throw CatalogError.duplicateID(entity: entity, id: id)
            }
        }
    }
}
