import CoreData

@objc(ProductEntity)
nonisolated final class ProductEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var name: String
    @NSManaged var brand: String?
    @NSManaged var category: String?
    @NSManaged var productType: String?
    @NSManaged var packageQuantity: NSDecimalNumber?
    @NSManaged var packageQuantityText: String?
    @NSManaged var packageUnit: String?
    @NSManaged var offers: Set<OfferEntity>

    func catalogValue() throws -> CatalogProduct {
        let quantity = try ExactDecimal.decode(packageQuantityText, legacy: packageQuantity, entity: "Product", id: id)
        return CatalogProduct(id: id, name: name, brand: brand, category: category,
                              productType: productType, packageQuantity: quantity, packageUnit: packageUnit)
    }
}

@objc(StoreEntity)
nonisolated final class StoreEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var name: String
    @NSManaged var chainName: String?
    @NSManaged var address: String?
    @NSManaged var latitude: NSNumber?
    @NSManaged var longitude: NSNumber?
    @NSManaged var isActive: Bool
    @NSManaged var format: String?
    @NSManaged var offers: Set<OfferEntity>

    var value: CatalogStore {
        CatalogStore(id: id, name: name, chainName: chainName, address: address,
                     latitude: latitude?.doubleValue, longitude: longitude?.doubleValue,
                     isActive: isActive, format: format)
    }
}

@objc(OfferEntity)
nonisolated final class OfferEntity: NSManagedObject {
    @NSManaged var id: String
    // Optional in the model to support unique constraints; both are required by the cache.
    @NSManaged var product: ProductEntity?
    @NSManaged var store: StoreEntity?
    @NSManaged var price: NSDecimalNumber
    @NSManaged var priceText: String?
    @NSManaged var currency: String
    @NSManaged var inStock: NSNumber?
    @NSManaged var sourceUpdatedAt: Date?
    @NSManaged var cachedAt: Date
    @NSManaged var sourceID: String?
    @NSManaged var sourceProductID: String?
    @NSManaged var sourceURL: String?
    @NSManaged var matchStatus: String?
    @NSManaged var dataOrigin: String?
    @NSManaged var priceType: String?
    @NSManaged var cardPriceText: String?
    @NSManaged var priceConditions: String?

    func cacheValue() throws -> StoredCatalogOffer {
        guard let product, let store else { throw CatalogError.missingReference(offerID: id) }
        guard let amount = try ExactDecimal.decode(priceText, legacy: price, entity: "Offer", id: id) else {
            throw CatalogError.invalidRecord(entity: "Offer", id: id)
        }
        let offer = CatalogOffer(
            id: id, productID: product.id, storeID: store.id,
            price: amount, currency: currency, inStock: inStock?.boolValue,
            sourceUpdatedAt: sourceUpdatedAt, sourceID: sourceID,
            sourceProductID: sourceProductID, sourceURL: sourceURL.flatMap(URL.init(string:)),
            matchStatus: matchStatus, dataOrigin: dataOrigin, priceType: priceType,
            cardPrice: try ExactDecimal.decode(cardPriceText, legacy: nil, entity: "Offer", id: id),
            priceConditions: priceConditions
        )
        return StoredCatalogOffer(offer: offer, cachedAt: cachedAt)
    }
}

@objc(CatalogMetadataEntity)
nonisolated final class CatalogMetadataEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var importID: Int64
    @NSManaged var importedAt: Date
    @NSManaged var isSynthetic: Bool
    @NSManaged var offerMaxAgeHours: Int64
    @NSManaged var etag: String?
    @NSManaged var validatedAt: Date

    var value: CatalogMetadata {
        CatalogMetadata(importID: importID, importedAt: importedAt, isSynthetic: isSynthetic,
                        offerMaxAgeHours: Int(offerMaxAgeHours), etag: etag, validatedAt: validatedAt)
    }
}
