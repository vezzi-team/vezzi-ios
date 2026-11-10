import CoreData

/// Disk persistence only. Queries and source coordination belong to the app repository.
@MainActor
final class CoreDataCatalogCache: CatalogCache {
    private let persistence: PersistenceController
    private var pendingWrite: Task<Void, Error>?

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    nonisolated deinit {}

    func loadSnapshot() async throws -> CatalogSnapshot {
        _ = await pendingWrite?.result
        return try await persistence.performSnapshotRead { context in
            let products = try context.fetch(NSFetchRequest<ProductEntity>(entityName: "ProductEntity"))
            let stores = try context.fetch(NSFetchRequest<StoreEntity>(entityName: "StoreEntity"))
            let request = NSFetchRequest<OfferEntity>(entityName: "OfferEntity")
            request.relationshipKeyPathsForPrefetching = ["product", "store"]
            let offers = try context.fetch(request)
            var batch = try CatalogCacheBatch(products: products.map { try $0.catalogValue() },
                                              stores: stores.map(\.value),
                                              offers: offers.map { try $0.cacheValue() })
            batch.metadata = try context.fetch(NSFetchRequest<CatalogMetadataEntity>(entityName: "CatalogMetadataEntity")).first?.value
            return try CatalogSnapshot().applying(batch).snapshot
        }
    }

    func save(_ batch: CatalogCacheBatch) async throws {
        // Also protect stable IDs when the adapter is used by concurrent callers.
        let previous = pendingWrite
        let task = Task { [persistence] in
            _ = await previous?.result
            try Task.checkCancellation()
            try await persistence.load()
            try Task.checkCancellation()
            try await persistence.container.performBackgroundTask { context in
                context.name = "Catalog cache write"
                context.undoManager = nil
                context.mergePolicy = NSErrorMergePolicy
                try CatalogImporter.apply(batch, to: context)
            }
        }
        pendingWrite = task
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
