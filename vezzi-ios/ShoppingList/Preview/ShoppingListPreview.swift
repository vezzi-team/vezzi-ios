import Foundation

/// Explicit fixtures for previews and UI verification. Never wired to production dependencies.
@MainActor
enum ShoppingListPreview {
    static let snapshot = SearchMockData.snapshot()

    static func repository() -> ShoppingListRepository {
        let selected = ProductMockData.products.prefix(4).compactMap { snapshot.products[$0.id] }
        let cart = ShoppingCart(id: UUID(), name: Texts.ShoppingList.title, status: "active",
                                items: selected.map { ShoppingCartItem(product: $0, quantity: 1) })
        return ShoppingListRepository(service: PreviewShoppingListService(cart: cart, snapshot: snapshot))
    }
}

private actor PreviewShoppingListService: ShoppingListService {
    private var value: ShoppingCart
    private let snapshot: CatalogSnapshot

    init(cart: ShoppingCart, snapshot: CatalogSnapshot) {
        value = cart
        self.snapshot = snapshot
    }

    func activeCart() -> ShoppingCart? { value }
    func cart(id: UUID) -> ShoppingCart { value }
    func createCart(name: String) -> ShoppingCart { value }

    func updateItem(cartID: UUID, productID: String, quantity: Int, exists: Bool) throws -> ShoppingCart {
        guard let product = snapshot.products[productID] else { throw APIError.invalidResponse }
        var items = value.items.filter { $0.product.id != productID }
        if quantity > 0 { items.append(ShoppingCartItem(product: product, quantity: quantity)) }
        value = ShoppingCart(id: value.id, name: value.name, status: value.status, items: items)
        return value
    }

    func plans(cartID: UUID, start: ShoppingCoordinate) -> ShoppingPlanResult {
        let stores = snapshot.stores.values.sorted { $0.id < $1.id }
        let cheapest = plan(stores: stores, fastest: false, start: start)
        let fastest = plan(stores: Array(stores.prefix(1)), fastest: true, start: start)
        return ShoppingPlanResult(plans: [cheapest, fastest], baselinePrice: fastest.total, problem: nil, isSynthetic: false)
    }

    private func plan(stores: [CatalogStore], fastest: Bool, start: ShoppingCoordinate) -> ShoppingPlan {
        var groups: [Int: [ShoppingPlanItem]] = [:]
        for (index, item) in value.items.enumerated() {
            let price = snapshot.offers.values.filter { $0.offer.productID == item.product.id }.map(\.offer.price).min() ?? 99
            let planned = ShoppingPlanItem(product: item.product, quantity: item.quantity,
                                           unitPrice: price + (fastest ? 5 : 0), cardPrice: nil, priceConditions: nil)
            groups[index % max(stores.count, 1), default: []].append(planned)
        }
        let stops = stores.enumerated().compactMap { index, original -> ShoppingPlanStop? in
            guard let items = groups[index] else { return nil }
            var store = original
            store.latitude = start.latitude + Double(index + 1) * 0.002
            store.longitude = start.longitude + Double(index + 1) * 0.003
            return ShoppingPlanStop(position: index + 1, store: store, items: items,
                                    subtotal: items.reduce(0) { $0 + $1.unitPrice * Decimal($1.quantity) })
        }
        let total = stops.reduce(Decimal.zero) { $0 + $1.subtotal }
        return ShoppingPlan(id: UUID(), total: total,
                            savings: fastest ? 0 : Decimal(value.items.reduce(0) { $0 + $1.quantity }) * 5,
                            totalSeconds: fastest ? 780 : 1080, walkingMeters: fastest ? 800 : 1300,
                            stops: stops, points: [start] + stops.compactMap {
                                guard let latitude = $0.store.latitude, let longitude = $0.store.longitude else { return nil }
                                return ShoppingCoordinate(latitude: latitude, longitude: longitude)
                            }, usesRoadNetwork: false, isSynthetic: false)
    }
}
