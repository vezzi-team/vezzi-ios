import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let catalog: any CatalogRepository
    let authentication: AuthenticationSession

    convenience init() {
        self.init(cache: CoreDataCatalogCache(persistence: PersistenceController()))
    }

    init(
        cache: (any CatalogCache)?,
        source: (any CatalogSource)? = nil,
        authenticationService: any AuthenticationService = MockAuthenticationService()
    ) {
        catalog = DefaultCatalogRepository(cache: cache, source: source)
        authentication = AuthenticationSession(service: authenticationService)
    }

    nonisolated deinit {}

    func load() async {
        await catalog.prepareCache()
    }
}
