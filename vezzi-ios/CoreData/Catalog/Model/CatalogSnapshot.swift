import Foundation

/// Immutable snapshots cross executors; indexes are maintained when data changes.
nonisolated struct CatalogSnapshot: Sendable {
    private(set) var products: [String: CatalogProduct] = [:]
    private(set) var stores: [String: CatalogStore] = [:]
    private(set) var offers: [String: StoredCatalogOffer] = [:]
    private(set) var metadata: CatalogMetadata?
    private var evaluationDate = Date()
    private var sortedProductIDs: [String] = []
    private var offerIDsByProduct: [String: Set<String>] = [:]

    func applying(_ batch: CatalogCacheBatch) throws -> (snapshot: Self, changes: CatalogRecordIDs) {
        try Task.checkCancellation()
        try batch.validate()
        var result = batch.replacesCatalog ? Self() : self
        var changes = CatalogRecordIDs()
        if let metadata = batch.metadata, result.metadata != metadata {
            result.metadata = metadata
            changes.metadata = true
        }
        for product in batch.products where result.products[product.id] != product {
            try Task.checkCancellation()
            result.products[product.id] = product
            changes.products.insert(product.id)
        }
        for store in batch.stores where result.stores[store.id] != store {
            try Task.checkCancellation()
            result.stores[store.id] = store
            changes.stores.insert(store.id)
        }
        for record in batch.offers {
            try Task.checkCancellation()
            let offer = record.offer
            guard result.products[offer.productID] != nil, result.stores[offer.storeID] != nil else {
                throw CatalogError.missingReference(offerID: offer.id)
            }
            let previous = result.offers[offer.id]
            guard offer.canReplace(sourceDate: previous?.offer.sourceUpdatedAt), previous != record else { continue }
            if let previous, previous.offer.productID != offer.productID {
                result.offerIDsByProduct[previous.offer.productID]?.remove(offer.id)
            }
            result.offers[offer.id] = record
            result.offerIDsByProduct[offer.productID, default: []].insert(offer.id)
            changes.offers.insert(offer.id)
        }
        if !changes.products.isEmpty { result.sortProducts() }
        return (result, changes)
    }

    /// A late cache may add records, but must not roll back newer source results.
    func mergingCache(_ cache: Self) -> Self {
        // A complete server snapshot is authoritative, including absent records.
        if metadata != nil { return self }
        var result = cache
        result.products.merge(products) { _, current in current }
        result.stores.merge(stores) { _, current in current }
        for (id, record) in offers where record.offer.canReplace(sourceDate: result.offers[id]?.offer.sourceUpdatedAt) {
            result.offers[id] = record
        }
        result.sortProducts()
        result.offerIDsByProduct = [:]
        for record in result.offers.values {
            result.offerIDsByProduct[record.offer.productID, default: []].insert(record.id)
        }
        return result
    }

    func changes(comparedTo stored: Self) -> CatalogRecordIDs {
        CatalogRecordIDs(
            products: Set(products.keys.filter { products[$0] != stored.products[$0] }),
            stores: Set(stores.keys.filter { stores[$0] != stored.stores[$0] }),
            offers: Set(offers.keys.filter { offers[$0] != stored.offers[$0] }),
            metadata: metadata != stored.metadata
        )
    }

    func cacheBatch(for ids: CatalogRecordIDs) -> CatalogCacheBatch {
        let records = ids.offers.compactMap { offers[$0] }
        // Include only the referenced parents, so a delta is valid after cache recovery too.
        let productIDs = ids.products.union(records.map { $0.offer.productID })
        let storeIDs = ids.stores.union(records.map { $0.offer.storeID })
        var batch = CatalogCacheBatch(products: productIDs.compactMap { products[$0] },
                                      stores: storeIDs.compactMap { stores[$0] }, offers: records)
        batch.metadata = ids.metadata ? metadata : nil
        return batch
    }

    func fullCacheBatch() -> CatalogCacheBatch {
        var batch = CatalogCacheBatch(products: Array(products.values), stores: Array(stores.values), offers: Array(offers.values))
        batch.metadata = metadata
        batch.replacesCatalog = true
        return batch
    }

    func allItems() -> [CatalogItem] { sortedProductIDs.compactMap { products[$0] }.map(item) }

    func validated(at date: Date) -> Self {
        var result = self
        result.metadata?.validatedAt = date
        result.evaluationDate = date
        return result
    }

    func evaluated(at date: Date) -> Self {
        var result = self
        result.evaluationDate = date
        return result
    }

    func items(matching query: String) -> [CatalogItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let matches = sortedProductIDs.lazy.compactMap { products[$0] }.filter { product in
            words.allSatisfy { word in
                [product.name, product.brand, product.category].compactMap { $0 }.contains {
                    $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
            }
        }.prefix(CatalogSearch.resultLimit)

        return matches.map(item)
    }

    func relatedItems(to productID: String, storeID: String? = nil) -> [CatalogItem] {
        guard let product = products[productID] else { return [] }
        let candidates = sortedProductIDs.lazy.compactMap { products[$0] }
            .filter { $0.id != productID && $0.groupID == product.groupID }
            .map(item)
            .filter { item in
                guard let storeID else { return true }
                return item.offers.contains { $0.store.id == storeID && $0.offer.inStock != false }
            }
            .prefix(CatalogSearch.resultLimit)
        return Array(candidates)
    }

    private func item(for product: CatalogProduct) -> CatalogItem {
        let availableOffers = (offerIDsByProduct[product.id] ?? []).compactMap { id -> CachedOffer? in
            guard let record = offers[id], let store = stores[record.offer.storeID], store.isActive else { return nil }
            let fresh = metadata.map { metadata in
                record.offer.sourceUpdatedAt.map { evaluationDate.timeIntervalSince($0) <= Double(metadata.offerMaxAgeHours) * 3600 } ?? false
            } ?? true
            return CachedOffer(offer: record.offer, store: store, cachedAt: record.cachedAt, isFresh: fresh)
        }
        .sorted { $0.store.name == $1.store.name ? $0.id < $1.id : $0.store.name < $1.store.name }
        return CatalogItem(product: product, offers: availableOffers)
    }

    private mutating func sortProducts() {
        sortedProductIDs = products.values.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }.map(\.id)
    }
}
