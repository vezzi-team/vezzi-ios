import Combine
import Foundation

@MainActor
final class StorefrontViewModel: ObservableObject {
    @Published private(set) var shelves = HomeShelves()
    @Published private var catalogHasProducts: Bool?
    @Published private(set) var products: [Product] = []
    @Published private(set) var catalogSections: [CatalogSection] = []
    @Published private(set) var catalogStatus = CatalogStatus()
    @Published private var cacheState = CatalogCacheState.disabled
    @Published private(set) var selectedDetail: StorefrontProductDetail?
    @Published private(set) var relatedProducts: [Product] = []
    let selection: ProductSelection
    let list: ShoppingListRepository
    private let repository: any CatalogRepository
    private var subscriptions = Set<AnyCancellable>()
    private var relatedSubscription: AnyCancellable?

    init(page: StorefrontPage, repository: any CatalogRepository, list: ShoppingListRepository? = nil) {
        self.repository = repository
        let list = list ?? ShoppingListRepository()
        self.list = list
        self.selection = list.selection
        list.$originAddress.removeDuplicates().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        repository.status.sink { [weak self] in self?.catalogStatus = $0 }.store(in: &subscriptions)
        repository.cacheState.removeDuplicates().sink { [weak self] in self?.cacheState = $0 }.store(in: &subscriptions)
        repository.observeAllProducts().sink { [weak self] items in
            guard let self else { return }
            self.catalogHasProducts = !items.isEmpty
            switch page {
            case .home:
                self.shelves = HomeShelves(items: items)
            case .collection(let collection):
                self.products = collection.products(from: items)
            case .catalog:
                self.catalogSections = CatalogSection.sections(from: items)
            }
        }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    var isCacheUnavailable: Bool { cacheState == .unavailable }
    var hasProducts: Bool { catalogHasProducts == true }
    var emptyState: CatalogEmptyState {
        guard catalogHasProducts != nil else { return .loading }
        return CatalogEmptyState(status: catalogStatus, cacheState: cacheState)
    }

    func refresh() async {
        async let cache: Void = repository.prepareCache()
        if repository.canRefresh { try? await repository.refresh() }
        await cache
    }

    func showProduct(_ product: Product, promotion: ProductOffer? = nil) {
        relatedSubscription?.cancel()
        relatedProducts = []
        selectedDetail = StorefrontProductDetail(product: product, promotion: promotion)
        relatedSubscription = repository.observeRelatedProducts(to: product.id, storeID: nil)
            .prefix(1).sink { [weak self] in self?.relatedProducts = $0.map { Product(catalog: $0) } }
    }

    func dismissProduct() {
        relatedSubscription?.cancel()
        relatedSubscription = nil
        selectedDetail = nil
        // Keep the snapshot alive until the sheet's dismissal animation ends.
    }
}

enum StorefrontCollection: Hashable, Identifiable {
    case moti(MotiCollection)
    case category(ProductCategory)

    var id: Self { self }

    var title: String {
        switch self {
        case .moti(let collection): collection.title
        case .category(let category): category.title
        }
    }

    func products(from items: [CatalogItem]) -> [Product] {
        switch self {
        case .moti(let collection): collection.products(from: items)
        case .category(let category):
            items.compactMap { ProductCategory(catalogValue: $0.product.category) == category ? Product(catalog: $0) : nil }
        }
    }
}

struct StorefrontProductDetail: Identifiable {
    let product: Product
    let promotion: ProductOffer?
    var id: String { product.id }
}

enum StorefrontPage: Equatable {
    case home, catalog
    case collection(StorefrontCollection)

    var tab: AppRouter.Tab {
        switch self {
        case .catalog, .collection(.category): .catalog
        case .home, .collection(.moti): .home
        }
    }
}
