import Foundation

nonisolated protocol ShoppingListCache: Sendable {
    func load(account: ShoppingListAccount) async throws -> ShoppingListCacheSnapshot?
    func save(_ snapshot: ShoppingListCacheSnapshot, account: ShoppingListAccount) async throws
    func remove(account: ShoppingListAccount) async throws
}

/// The last acknowledged cart and absolute local edits are saved together.
nonisolated struct ShoppingListCacheSnapshot: Codable, Sendable {
    var cart: ShoppingCart?
    var pending: [ShoppingCartEditTarget: [String: Int]]
    var plan: CachedShoppingPlan?
    /// A successful lookup can confirm that the account has no active cart.
    var hasResolvedCart: Bool

    init(cart: ShoppingCart?, pending: [ShoppingCartEditTarget: [String: Int]], plan: CachedShoppingPlan?,
         hasResolvedCart: Bool = false) {
        self.cart = cart
        self.pending = pending
        self.plan = plan
        self.hasResolvedCart = hasResolvedCart || cart != nil
    }

    private enum CodingKeys: String, CodingKey { case cart, pending, plan, hasResolvedCart }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cart = try values.decodeIfPresent(ShoppingCart.self, forKey: .cart)
        pending = try values.decode([ShoppingCartEditTarget: [String: Int]].self, forKey: .pending)
        plan = try values.decodeIfPresent(CachedShoppingPlan.self, forKey: .plan)
        // Older snapshots also saved nil after a failed first request; only an actual cart is proof.
        hasResolvedCart = try values.decodeIfPresent(Bool.self, forKey: .hasResolvedCart) ?? (cart != nil)
    }

    func validate() throws {
        if let cart {
            guard hasResolvedCart, cart.status == "active", cart.items.count <= 30,
                  Set(cart.items.map { $0.product.id }).count == cart.items.count,
                  cart.items.allSatisfy({ !$0.product.id.isEmpty && (1...99).contains($0.quantity) }) else {
                throw ShoppingListCacheError.invalidSnapshot
            }
        }
        guard pending.values.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ !$0.key.isEmpty && (0...99).contains($0.value) }) }) else {
            throw ShoppingListCacheError.invalidSnapshot
        }
        // Remote additions can make the cart plus local edits exceed the server's limit.
        // Preserve that conflict on disk; synchronization enforces the limit before adding items.
        if let plan {
            guard pending[.active] == nil, let cart, pending[.cart(cart.id)] == nil, plan.matches(cart),
                  plan.calculatedAt.timeIntervalSince1970.isFinite,
                  plan.result.baselinePrice.map({ $0 >= .zero }) ?? true,
                  plan.result.plans.count <= 3,
                  Set(plan.result.plans.map(\.id)).count == plan.result.plans.count else {
                throw ShoppingListCacheError.invalidSnapshot
            }
            for option in plan.result.plans {
                let items = option.stops.flatMap(\.items)
                guard option.total >= .zero, option.totalSeconds >= 0, option.walkingMeters >= 0, !option.stops.isEmpty,
                      Set(option.stops.map(\.id)).count == option.stops.count,
                      Set(items.map { $0.product.id }).count == items.count,
                      items.allSatisfy({ (1...99).contains($0.quantity) && $0.unitPrice >= .zero
                          && ($0.cardPrice.map { $0 >= .zero } ?? true) }),
                      option.stops.allSatisfy({ !$0.id.isEmpty && $0.position > 0 && $0.subtotal >= .zero }),
                      option.points.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }),
                      Dictionary(items.map { ($0.product.id, $0.quantity) }, uniquingKeysWith: +) == cart.quantities else {
                    throw ShoppingListCacheError.invalidSnapshot
                }
            }
        }
    }
}

nonisolated struct CachedShoppingPlan: Codable, Sendable {
    let cartID: UUID
    let quantities: [String: Int]
    let origin: ShoppingCoordinate
    let calculatedAt: Date
    let result: ShoppingPlanResult

    func matches(_ cart: ShoppingCart) -> Bool {
        cartID == cart.id && quantities == cart.quantities
    }
}

nonisolated enum ShoppingListCacheError: Error {
    case invalidSnapshot
}
