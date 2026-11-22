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
    var origin: ShoppingCoordinate
    var originAddress: String?
    var routeOptions: ShoppingRouteOptions
    var trip: ShoppingTrip?

    init(cart: ShoppingCart?, pending: [ShoppingCartEditTarget: [String: Int]], plan: CachedShoppingPlan?,
         hasResolvedCart: Bool = false, origin: ShoppingCoordinate? = nil, routeOptions: ShoppingRouteOptions = .init(),
         originAddress: String? = nil, trip: ShoppingTrip? = nil) {
        self.cart = cart
        self.pending = pending
        self.plan = plan
        self.hasResolvedCart = hasResolvedCart || cart != nil
        self.origin = origin ?? plan?.origin ?? .defaultOrigin
        self.originAddress = originAddress
        self.routeOptions = routeOptions
        self.trip = trip
    }

    private enum CodingKeys: String, CodingKey { case cart, pending, plan, hasResolvedCart, origin, routeOptions, originAddress, trip }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cart = try values.decodeIfPresent(ShoppingCart.self, forKey: .cart)
        pending = try values.decode([ShoppingCartEditTarget: [String: Int]].self, forKey: .pending)
        plan = try values.decodeIfPresent(CachedShoppingPlan.self, forKey: .plan)
        // Older snapshots also saved nil after a failed first request; only an actual cart is proof.
        hasResolvedCart = try values.decodeIfPresent(Bool.self, forKey: .hasResolvedCart) ?? (cart != nil)
        origin = try values.decodeIfPresent(ShoppingCoordinate.self, forKey: .origin) ?? plan?.origin ?? .previewOrigin
        originAddress = try values.decodeIfPresent(String.self, forKey: .originAddress)
        routeOptions = try values.decodeIfPresent(ShoppingRouteOptions.self, forKey: .routeOptions) ?? .init()
        trip = try values.decodeIfPresent(ShoppingTrip.self, forKey: .trip)
    }

    func validate() throws {
        guard origin.isValid, routeOptions.isValid else { throw ShoppingListCacheError.invalidSnapshot }
        if let trip {
            let items = trip.items
            let itemIDs = Set(items.compactMap(\.itemID))
            guard trip.cartID == cart?.id, trip.origin.isValid, trip.contains(trip.page), !trip.plan.stops.isEmpty,
                  !items.isEmpty, itemIDs.count == items.count,
                  items.allSatisfy({ ($0.itemID ?? 0) > 0 && $0.status != nil }) else {
                throw ShoppingListCacheError.invalidSnapshot
            }
            if let marks = trip.pendingMarks {
                guard itemIDs.isSuperset(of: marks.keys), items.allSatisfy({ item in
                    guard let id = item.itemID, let desired = marks[id] else { return true }
                    return item.status == desired
                }) else { throw ShoppingListCacheError.invalidSnapshot }
            }
        }
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
            guard pending[.active] == nil, let cart, pending[.cart(cart.id)] == nil, plan.matches(cart), plan.origin == origin,
                  plan.routeOptions == routeOptions,
                  plan.calculatedAt.timeIntervalSince1970.isFinite,
                  plan.result.baselinePrice.map({ $0 >= .zero }) ?? true,
                  plan.result.hasValidRankings else {
                throw ShoppingListCacheError.invalidSnapshot
            }
            for option in plan.result.rankedPlans {
                let items = option.stops.flatMap(\.items)
                guard option.total >= .zero, option.totalSeconds >= 0, option.walkingMeters >= 0, !option.stops.isEmpty,
                      option.returnWalkingSeconds.map({ $0 >= 0 }) ?? true,
                      option.returnWalkingMeters.map({ $0 >= 0 }) ?? true,
                      Set(option.stops.map(\.id)).count == option.stops.count,
                      Set(items.map { $0.product.id }).count == items.count,
                      items.allSatisfy({ (1...99).contains($0.quantity) && $0.unitPrice >= .zero
                          && ($0.cardPrice.map { $0 >= .zero } ?? true) }),
                      option.stops.allSatisfy({ !$0.id.isEmpty && $0.position > 0 && $0.subtotal >= .zero }),
                      option.stops.allSatisfy({ ($0.walkingSeconds.map { $0 >= 0 } ?? true)
                          && ($0.walkingMeters.map { $0 >= 0 } ?? true) }),
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
    let routeOptions: ShoppingRouteOptions

    init(cartID: UUID, quantities: [String: Int], origin: ShoppingCoordinate, calculatedAt: Date,
         result: ShoppingPlanResult, routeOptions: ShoppingRouteOptions = .init()) {
        self.cartID = cartID
        self.quantities = quantities
        self.origin = origin
        self.calculatedAt = calculatedAt
        self.result = result
        self.routeOptions = routeOptions
    }

    private enum CodingKeys: String, CodingKey { case cartID, quantities, origin, calculatedAt, result, routeOptions }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cartID = try values.decode(UUID.self, forKey: .cartID)
        quantities = try values.decode([String: Int].self, forKey: .quantities)
        origin = try values.decode(ShoppingCoordinate.self, forKey: .origin)
        calculatedAt = try values.decode(Date.self, forKey: .calculatedAt)
        result = try values.decode(ShoppingPlanResult.self, forKey: .result)
        // Existing snapshots were one-way calculations without a radius limit.
        routeOptions = try values.decodeIfPresent(ShoppingRouteOptions.self, forKey: .routeOptions) ?? .init()
    }

    func matches(_ cart: ShoppingCart) -> Bool {
        cartID == cart.id && quantities == cart.quantities
    }
}

nonisolated enum ShoppingListCacheError: Error {
    case invalidSnapshot
}
