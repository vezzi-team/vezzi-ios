import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    let products = HomeMockData.products
    @Published var selectedAddress = HomeAddress.home
    @Published private(set) var quantities: [String: Int] = [:]

    nonisolated deinit {}

    static let quantityRange = 0...99

    var hasDinnerProducts: Bool {
        HomeMockData.dinnerProductIDs.allSatisfy { quantity(for: $0) > 0 }
    }

    func quantity(for productID: String) -> Int { quantities[productID, default: 0] }

    func alternatives(for productID: String) -> [HomeProduct] {
        HomeMockData.alternatives(for: productID)
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
