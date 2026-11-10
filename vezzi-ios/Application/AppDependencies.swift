import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let catalog: DefaultCatalogRepository
    let authentication: AuthenticationSession
    private var networkMonitor: NetworkMonitor?
    private var hasLoaded = false
    private var hasStarted = false
    private var statusSubscription: AnyCancellable?

    convenience init() {
        let authentication = DefaultAuthenticationService()
        self.init(cache: CoreDataCatalogCache(persistence: PersistenceController()),
                  source: APICatalogSource(client: authentication), authenticationService: authentication)
        networkMonitor = NetworkMonitor { [weak self] connected in
            self?.catalog.updateConnectivity(isConnected: connected)
        }
    }

    init(
        cache: (any CatalogCache)?,
        source: (any CatalogSource)? = nil,
        authenticationService: any AuthenticationService = DefaultAuthenticationService()
    ) {
        catalog = DefaultCatalogRepository(cache: cache, source: source)
        authentication = AuthenticationSession(service: authenticationService, startsRestoring: true)
        statusSubscription = catalog.status.map(\.failure).removeDuplicates().sink { [weak self] failure in
            guard failure == .authenticationRequired else { return }
            Task { await self?.authentication.restore(force: true) }
        }
    }

    nonisolated deinit {}

    func load() async {
        guard !hasStarted else { return }
        hasStarted = true
        async let cache: Void = catalog.prepareCache()
        await authentication.restore()
        if catalog.canRefresh { try? await catalog.refresh() }
        hasLoaded = true
        await cache
    }

    func accountChanged() async {
        guard hasStarted else { return }
        catalog.cancelRefresh()
        if catalog.canRefresh { try? await catalog.refresh() }
    }

    func becameActive() async {
        guard hasLoaded else { return }
        await authentication.restore(force: true)
        if catalog.canRefresh { try? await catalog.refresh() }
    }
}
