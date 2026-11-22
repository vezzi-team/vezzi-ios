import Combine

/// Shared quantities; the shopping-list repository synchronizes account-owned changes.
@MainActor
final class ProductSelection: ObservableObject {
    @Published private(set) var quantities: [String: Int] = [:]
    @Published private(set) var feedbackRevision = 0
    @Published private(set) var hasAddedProductThisSession = false
    @Published var showsLimitAlert = false
    @Published var showsShoppingAlert = false
    var isShopping = false

    static let quantityRange = 0...99
    static let maximumProductCount = 30

    nonisolated deinit {}

    func quantity(for productID: String) -> Int { quantities[productID, default: 0] }

    subscript(productID id: String) -> Int {
        get { quantity(for: id) }
        set { setQuantity(newValue, for: id) }
    }

    func setQuantity(_ quantity: Int, for productID: String) {
        guard !isShopping else {
            showsShoppingAlert = true
            return
        }
        let value = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
        let previous = self.quantity(for: productID)
        guard value != previous else { return }
        guard value == 0 || quantities[productID] != nil || quantities.count < Self.maximumProductCount else {
            showsLimitAlert = true
            return
        }
        quantities[productID] = value == 0 ? nil : value
        feedbackRevision += 1
        if previous == 0 && !hasAddedProductThisSession {
            hasAddedProductThisSession = true
        }
    }

    /// Applying server state must not trigger user-action haptics or another network mutation.
    func replaceQuantities(_ values: [String: Int]) {
        guard quantities != values else { return }
        quantities = values
    }
}
