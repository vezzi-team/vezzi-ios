import CoreData

nonisolated enum CatalogImporter {
    /// Runs entirely on the supplied private context's queue and saves once.
    static func apply(_ records: CatalogCacheBatch, to context: NSManagedObjectContext) throws {
        do {
            try records.validate()
            let batch = records.values
            let products: [String: ProductEntity] = try existing(
                "ProductEntity", ids: batch.products.map(\.id) + batch.offers.map(\.productID), in: context
            )
            let stores: [String: StoreEntity] = try existing(
                "StoreEntity", ids: batch.stores.map(\.id) + batch.offers.map(\.storeID), in: context
            )
            let offers: [String: OfferEntity] = try existing("OfferEntity", ids: batch.offers.map(\.id), in: context)
            var productByID = products
            var storeByID = stores

            for value in batch.products {
                try Task.checkCancellation()
                let object = products[value.id] ?? NSEntityDescription.insertNewObject(
                    forEntityName: "ProductEntity", into: context
                ) as! ProductEntity
                object.id = value.id
                object.name = value.name
                object.brand = value.brand
                object.category = value.category
                object.productType = value.productType
                // Legacy numeric fields are retained for version-1 migration compatibility.
                object.packageQuantity = value.packageQuantity.map(NSDecimalNumber.init(decimal:))
                object.packageQuantityText = value.packageQuantity.map(ExactDecimal.encode)
                object.packageUnit = value.packageUnit
                productByID[value.id] = object
            }

            for value in batch.stores {
                try Task.checkCancellation()
                let object = stores[value.id] ?? NSEntityDescription.insertNewObject(
                    forEntityName: "StoreEntity", into: context
                ) as! StoreEntity
                object.id = value.id
                object.name = value.name
                object.chainName = value.chainName
                object.address = value.address
                object.latitude = value.latitude.map(NSNumber.init(value:))
                object.longitude = value.longitude.map(NSNumber.init(value:))
                object.isActive = value.isActive
                storeByID[value.id] = object
            }

            for record in records.offers {
                let value = record.offer
                try Task.checkCancellation()
                guard let product = productByID[value.productID], let store = storeByID[value.storeID] else {
                    throw CatalogError.missingReference(offerID: value.id)
                }
                let existingOffer = offers[value.id]
                // An undated or older price must not replace a dated, newer price.
                guard value.canReplace(sourceDate: existingOffer?.sourceUpdatedAt) else { continue }
                let object = existingOffer ?? NSEntityDescription.insertNewObject(
                    forEntityName: "OfferEntity", into: context
                ) as! OfferEntity
                object.id = value.id
                object.product = product
                object.store = store
                object.price = NSDecimalNumber(decimal: value.price)
                object.priceText = ExactDecimal.encode(value.price)
                object.currency = value.currency
                object.inStock = value.inStock.map(NSNumber.init(value:))
                object.sourceUpdatedAt = value.sourceUpdatedAt
                object.cachedAt = record.cachedAt
                object.sourceID = value.sourceID
                object.sourceProductID = value.sourceProductID
                object.sourceURL = value.sourceURL?.absoluteString
                object.matchStatus = value.matchStatus
                object.dataOrigin = value.dataOrigin
                object.priceType = value.priceType
            }

            try Task.checkCancellation()
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func existing<T: NSManagedObject>(
        _ entity: String, ids: [String], in context: NSManagedObjectContext
    ) throws -> [String: T] {
        guard !ids.isEmpty else { return [:] }
        let request = NSFetchRequest<T>(entityName: entity)
        request.predicate = NSPredicate(format: "id IN %@", Array(Set(ids)))
        return Dictionary(uniqueKeysWithValues: try context.fetch(request).map {
            ($0.value(forKey: "id") as! String, $0)
        })
    }

}
