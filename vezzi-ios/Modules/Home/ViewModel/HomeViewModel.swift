import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var categories: [ProductCategory] = []
    @Published private(set) var catalogStatus = CatalogStatus()
    @Published private(set) var isCacheUnavailable = false
    @Published private(set) var selectedProduct: Product?
    @Published private(set) var relatedProducts: [Product] = []
    @Published var selectedAddress = HomeAddress.home
    @Published var selectedCategory: ProductCategory?
    let selection: ProductSelection
    private let repository: any CatalogRepository
    private var subscriptions = Set<AnyCancellable>()
    private var relatedSubscription: AnyCancellable?

    init(repository: any CatalogRepository, selection: ProductSelection? = nil) {
        self.repository = repository
        self.selection = selection ?? ProductSelection()
        self.selection.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        repository.status.sink { [weak self] in self?.catalogStatus = $0 }.store(in: &subscriptions)
        repository.cacheState.sink { [weak self] in self?.isCacheUnavailable = $0 == .unavailable }.store(in: &subscriptions)
        repository.observeAllProducts().sink { [weak self] items in
            guard let self else { return }
            self.products = items.map { Product(catalog: $0) }
            self.categories = Array(Set(self.products.compactMap(\.category))).sorted { $0.title < $1.title }
            if let category = self.selectedCategory, !self.categories.contains(category) { self.selectedCategory = nil }
        }.store(in: &subscriptions)
    }

    nonisolated deinit {}

    var quantities: [String: Int] { selection.quantities }
    var filteredProducts: [Product] { products(in: selectedCategory) }

    func refresh() async {
        async let cache: Void = repository.prepareCache()
        if repository.canRefresh { try? await repository.refresh() }
        await cache
    }

    func quantity(for productID: String) -> Int { selection.quantity(for: productID) }

    func products(in category: ProductCategory?) -> [Product] {
        guard let category else { return products }
        return products.filter { $0.category == category }
    }

    func setQuantity(_ quantity: Int, for productID: String) {
        selection.setQuantity(quantity, for: productID)
    }

    func showProduct(_ product: Product) {
        relatedSubscription?.cancel()
        relatedProducts = []
        selectedProduct = product
        relatedSubscription = repository.observeRelatedProducts(to: product.id, storeID: nil)
            .prefix(1).sink { [weak self] in self?.relatedProducts = $0.map { Product(catalog: $0) } }
    }

    func dismissProduct() {
        relatedSubscription?.cancel()
        relatedSubscription = nil
        selectedProduct = nil
        // Keep the snapshot alive until the sheet's dismissal animation ends.
    }
}
