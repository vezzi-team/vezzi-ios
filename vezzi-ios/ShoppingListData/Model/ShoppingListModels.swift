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

    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }

    // Prospekt Korolyova, 34 k2: a street address near the center of the supported area.
    static let defaultOrigin = Self(latitude: 60.014550, longitude: 30.258000)

    // Kept for fixtures and decoding legacy snapshots that predate the origin field.
    static let previewOrigin = Self(latitude: 60.0087, longitude: 30.2582)
}

/// Route constraints travel with the calculation and its cache identity.
nonisolated struct ShoppingRouteOptions: Codable, Sendable, Equatable {
    var returnToStart = false
    var radiusMeters: Int?

    static let radiusRange = 100...5000
    var isValid: Bool { radiusMeters.map(Self.radiusRange.contains) ?? true }
}

nonisolated struct ShoppingPlanResult: Codable, Sendable {
    let plans: [ShoppingPlan]
    /// Both rankings retain server order. Earlier disk snapshots contain only the price ranking.
    let fastestPlans: [ShoppingPlan]?
    let baselinePrice: Decimal?
    let problem: String?
    let isSynthetic: Bool
    var minRequiredRadiusMeters: Int? = nil

    var rankedPlans: [ShoppingPlan] { plans + (fastestPlans ?? []) }

    var hasValidRankings: Bool {
        func isValid(_ ranking: [ShoppingPlan]) -> Bool {
            ranking.count <= 3 && Set(ranking.map(\.id)).count == ranking.count
        }
        guard isValid(plans) else { return false }
        guard let fastestPlans else { return true }
        return fastestPlans.isEmpty == plans.isEmpty && isValid(fastestPlans)
    }
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
    var returnWalkingSeconds: Int? = nil
    var returnWalkingMeters: Int? = nil
}

nonisolated struct ShoppingPlanStop: Codable, Identifiable, Sendable {
    var id: String { store.id }
    let position: Int
    let store: CatalogStore
    let items: [ShoppingPlanItem]
    let subtotal: Decimal
    // Optional for previously cached calculations which did not retain leg metrics.
    var walkingSeconds: Int? = nil
    var walkingMeters: Int? = nil
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
