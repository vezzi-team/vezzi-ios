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
        authenticationService: any AuthenticationService = DefaultAuthenticationService()
    ) {
        catalog = DefaultCatalogRepository(cache: cache, source: source)
        authentication = AuthenticationSession(service: authenticationService, startsRestoring: true)
    }

    nonisolated deinit {}

    func load() async {
        async let cache: Void = catalog.prepareCache()
        async let session: Void = authentication.restore()
        _ = await (cache, session)
    }
}
