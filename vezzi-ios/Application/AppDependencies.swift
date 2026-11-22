import Combine
import Foundation

@MainActor
final class AppDependencies: ObservableObject {
    let catalog: DefaultCatalogRepository
    let authentication: AuthenticationSession
    let shoppingList: ShoppingListRepository
    let location: any DeviceLocating = DeviceLocationService()
    private var networkMonitor: NetworkMonitor?
    private var hasLoaded = false
    private var hasStarted = false
    private var accountSubscription: AnyCancellable?
    private var listStatusSubscription: AnyCancellable?

    convenience init() {
        let client = APIClient()
        let authentication = DefaultAuthenticationService(client: client)
        self.init(cache: CoreDataCatalogCache(persistence: PersistenceController()),
                  source: APICatalogSource(client: client), authenticationService: authentication, authenticationDefaults: .standard,
                  shoppingListService: APIShoppingListService(client: authentication), shoppingListCache: FileShoppingListCache(),
                  addressResolver: MapKitAddressResolver())
        networkMonitor = NetworkMonitor { [weak self] connected in
            self?.catalog.updateConnectivity(isConnected: connected)
            self?.shoppingList.updateConnectivity(isConnected: connected)
        }
    }

    init(
        cache: (any CatalogCache)?,
        source: (any CatalogSource)? = nil,
        authenticationService: any AuthenticationService = DefaultAuthenticationService(),
        authenticationDefaults: UserDefaults? = nil,
        shoppingListService: (any ShoppingListService)? = nil,
        shoppingListCache: (any ShoppingListCache)? = nil,
        addressResolver: (any AddressResolving)? = nil
    ) {
        catalog = DefaultCatalogRepository(cache: cache, source: source)
        authentication = AuthenticationSession(service: authenticationService, startsRestoring: true, defaults: authenticationDefaults)
        shoppingList = ShoppingListRepository(service: shoppingListService, cache: shoppingListCache, addressResolver: addressResolver)
        accountSubscription = authentication.$identity.map { identity in
            identity.map { ShoppingListAccount(id: $0.user.id.uuidString, sessionID: $0.sessionID) }
        }.removeDuplicates().sink { [weak self] account in
            self?.shoppingList.setAccount(account)
        }
        listStatusSubscription = shoppingList.$failure.merge(with: shoppingList.$tripFailure)
            .removeDuplicates().sink { [weak self] failure in
                guard failure == .authenticationRequired, let self, let sessionID = shoppingList.account?.sessionID else { return }
                Task { [weak self] in await self?.authentication.restore(afterRejectionOf: sessionID) }
            }
    }

    nonisolated deinit {}

    func load() async {
        guard !hasStarted else { return }
        hasStarted = true
        async let cache: Void = catalog.prepareCache()
        async let catalogRefresh: Void = refreshCatalog()
        await authentication.restore()
        await catalogRefresh
        hasLoaded = true
        await cache
    }

    func becameActive() async {
        guard hasLoaded else { return }
        async let catalogRefresh: Void = refreshCatalog()
        await authentication.restore(force: true)
        await shoppingList.refresh()
        await catalogRefresh
    }

    private func refreshCatalog() async {
        if catalog.canRefresh { try? await catalog.refresh() }
    }
}
