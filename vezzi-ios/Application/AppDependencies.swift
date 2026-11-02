import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let catalog: any CatalogRepository

    convenience init() {
        self.init(cache: CoreDataCatalogCache(persistence: PersistenceController()))
    }

    init(
        cache: (any CatalogCache)?,
        source: (any CatalogSource)? = nil
    ) {
        catalog = DefaultCatalogRepository(cache: cache, source: source)
    }

    nonisolated deinit {}

    func load() async {
        await catalog.prepareCache()
    }
}
