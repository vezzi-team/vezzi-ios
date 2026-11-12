import Foundation

/// Account-owned data is also scoped to the persisted sign-in session, never to its rotating tokens.
nonisolated struct ShoppingListAccount: Codable, Hashable, Sendable {
    let id: String
    let sessionID: UUID
}

/// Guest edits are bound once an active cart is resolved. Bound edits never move to another cart.
nonisolated enum ShoppingCartEditTarget: Codable, Hashable, Sendable {
    case active
    case cart(UUID)
}

nonisolated struct ShoppingCart: Codable, Sendable {
    let id: UUID
    let name: String
    let status: String
    let items: [ShoppingCartItem]

    var quantities: [String: Int] {
        Dictionary(items.map { ($0.product.id, $0.quantity) }, uniquingKeysWith: { _, latest in latest })
    }
}

nonisolated struct ShoppingCartItem: Codable, Sendable {
    let product: CatalogProduct
    let quantity: Int
}

nonisolated struct ShoppingCoordinate: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double

    // Temporary origin in the area covered by the current catalog; never a device location.
    static let previewOrigin = Self(latitude: 60.0087, longitude: 30.2582)
}

nonisolated struct ShoppingPlanResult: Codable, Sendable {
    let plans: [ShoppingPlan]
    let baselinePrice: Decimal?
    let problem: String?
    let isSynthetic: Bool
}

nonisolated struct ShoppingPlan: Codable, Identifiable, Sendable {
    let id: UUID
    let total: Decimal
    let savings: Decimal?
    let totalSeconds: Int
    let walkingMeters: Int
    let stops: [ShoppingPlanStop]
    let points: [ShoppingCoordinate]
    let usesRoadNetwork: Bool
    let isSynthetic: Bool
}

nonisolated struct ShoppingPlanStop: Codable, Identifiable, Sendable {
    var id: String { store.id }
    let position: Int
    let store: CatalogStore
    let items: [ShoppingPlanItem]
    let subtotal: Decimal
}

nonisolated struct ShoppingPlanItem: Codable, Sendable {
    let product: CatalogProduct
    let quantity: Int
    let unitPrice: Decimal
    let cardPrice: Decimal?
    let priceConditions: String?
}

nonisolated enum ShoppingListFailure: Error, Equatable {
    case authenticationRequired
    case offline
    case limit
    case cartUnavailable
    case otherCartSyncFailed
    case unavailable

    static func from(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if AuthenticationFailure.from(error).invalidatesSession || (error as? APIError)?.status == 401 {
            return .authenticationRequired
        }
        if let url = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut].contains(url.code) {
            return .offline
        }
        return .unavailable
    }
}
