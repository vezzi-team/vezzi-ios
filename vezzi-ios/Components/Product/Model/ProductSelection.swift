import Combine

/// Temporary quantities shared by storefront screens. No shopping-list persistence yet.
@MainActor
final class ProductSelection: ObservableObject {
    @Published private(set) var quantities: [String: Int] = [:]

    static let quantityRange = 0...99

    nonisolated deinit {}

    func quantity(for productID: String) -> Int { quantities[productID, default: 0] }

    func setQuantity(_ quantity: Int, for productID: String) {
        let value = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
        guard value != self.quantity(for: productID) else { return }
        quantities[productID] = value == 0 ? nil : value
    }
}
