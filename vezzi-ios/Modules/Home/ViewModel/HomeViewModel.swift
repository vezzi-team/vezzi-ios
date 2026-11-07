import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    let products = ProductMockData.products
    @Published var selectedAddress = HomeAddress.home
    @Published var selectedCategory: ProductCategory?
    let selection: ProductSelection
    private var selectionSubscription: AnyCancellable?

    init(selection: ProductSelection? = nil) {
        let selection = selection ?? ProductSelection()
        self.selection = selection
        selectionSubscription = selection.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    nonisolated deinit {}

    var quantities: [String: Int] { selection.quantities }

    var filteredProducts: [Product] {
        products(in: selectedCategory)
    }

    var hasDinnerProducts: Bool {
        ProductMockData.dinnerProductIDs.allSatisfy { quantity(for: $0) > 0 }
    }

    func quantity(for productID: String) -> Int { selection.quantity(for: productID) }

    func product(for productID: String) -> Product? {
        ProductMockData.product(for: productID)
    }

    func alternatives(for productID: String) -> [Product] {
        ProductMockData.alternatives(for: productID)
    }

    func products(in category: ProductCategory?) -> [Product] {
        guard let category else { return products }
        return products.filter { $0.category == category }
    }

    func setQuantity(_ quantity: Int, for productID: String) {
        guard ProductMockData.productIDs.contains(productID) else { return }
        selection.setQuantity(quantity, for: productID)
    }

    func addDinnerProducts() {
        for productID in ProductMockData.dinnerProductIDs where quantity(for: productID) == 0 {
            setQuantity(1, for: productID)
        }
    }
}
