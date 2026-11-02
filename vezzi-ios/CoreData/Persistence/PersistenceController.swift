import CoreData

@MainActor
final class PersistenceController {
    let container: NSPersistentContainer
    private var loadTask: Task<Void, Error>?

    init(storeURL: URL? = nil, inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Polka")

        let description = NSPersistentStoreDescription()
        description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
        description.url = inMemory ? nil : storeURL ?? NSPersistentContainer.defaultDirectoryURL()
            .appendingPathComponent("Polka.sqlite")
        description.shouldAddStoreAsynchronously = true
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        container.viewContext.undoManager = nil
    }

    nonisolated deinit {}

    /// Reads related records from one SQLite generation, even if another context saves.
    func performSnapshotRead<Value: Sendable>(
        _ read: @escaping @Sendable (NSManagedObjectContext) throws -> Value
    ) async throws -> Value {
        try await load()
        return try await container.performBackgroundTask { context in
            context.name = "Catalog cache read"
            context.undoManager = nil
            // Query generations are supported by SQLite, not the in-memory preview store.
            if context.persistentStoreCoordinator?.persistentStores.allSatisfy({ $0.type == NSSQLiteStoreType }) == true {
                try context.setQueryGenerationFrom(.current)
            }
            return try read(context)
        }
    }

    /// Opening failures are surfaced to the app; the user's store is never reset.
    func load() async throws {
        if let loadTask {
            return try await loadTask.value
        }

        let task = Task { [container] in
            if let url = container.persistentStoreDescriptions.first?.url {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                container.loadPersistentStores { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        loadTask = task
        do {
            try await task.value
        } catch {
            loadTask = nil
            throw error
        }
    }
}
