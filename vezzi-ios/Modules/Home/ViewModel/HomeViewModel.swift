import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    let products = HomeMockData.products
    @Published var selectedAddress = HomeAddress.home
    @Published var selectedCategory: HomeProductCategory?
    @Published private(set) var quantities: [String: Int] = [:]

    nonisolated deinit {}

    static let quantityRange = 0...99

    var filteredProducts: [HomeProduct] {
        products(in: selectedCategory)
    }

    var hasDinnerProducts: Bool {
        HomeMockData.dinnerProductIDs.allSatisfy { quantity(for: $0) > 0 }
    }

    func quantity(for productID: String) -> Int { quantities[productID, default: 0] }

    func product(for productID: String) -> HomeProduct? {
        HomeMockData.product(for: productID)
    }

    func alternatives(for productID: String) -> [HomeProduct] {
        HomeMockData.alternatives(for: productID)
    }

    func products(in category: HomeProductCategory?) -> [HomeProduct] {
        guard let category else { return products }
        return products.filter { $0.category == category }
    }

    func setQuantity(_ quantity: Int, for productID: String) {
        guard HomeMockData.productIDs.contains(productID) else { return }
        let value = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
        quantities[productID] = value == 0 ? nil : value
    }

    func addDinnerProducts() {
        for productID in HomeMockData.dinnerProductIDs where quantity(for: productID) == 0 {
            setQuantity(1, for: productID)
        }
    }
}
