import Combine

/// Shared quantities; the shopping-list repository synchronizes account-owned changes.
@MainActor
final class ProductSelection: ObservableObject {
    @Published private(set) var quantities: [String: Int] = [:]
    @Published private(set) var feedbackRevision = 0
    @Published var showsLimitAlert = false

    static let quantityRange = 0...99
    static let maximumProductCount = 30

    nonisolated deinit {}

    func quantity(for productID: String) -> Int { quantities[productID, default: 0] }

    func setQuantity(_ quantity: Int, for productID: String) {
        let value = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
        guard value != self.quantity(for: productID) else { return }
        guard value == 0 || quantities[productID] != nil || quantities.count < Self.maximumProductCount else {
            showsLimitAlert = true
            return
        }
        quantities[productID] = value == 0 ? nil : value
        feedbackRevision += 1
    }

    /// Applying server state must not trigger user-action haptics or another network mutation.
    func replaceQuantities(_ values: [String: Int]) {
        guard quantities != values else { return }
        quantities = values
    }
}
