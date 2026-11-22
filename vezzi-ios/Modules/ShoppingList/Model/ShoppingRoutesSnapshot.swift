import Foundation

/// A presentation snapshot remains valid while the list refreshes in the background.
nonisolated struct ShoppingRoutesSnapshot: Identifiable {
    let id = UUID()
    let plans: [ShoppingPlan]
    let mode: ShoppingMode
    let selectedID: UUID
    let origin: ShoppingCoordinate
    let originAddress: String?
    let isSaved: Bool
    let routeOptions: ShoppingRouteOptions
    let startsAtSummary: Bool

    init?(plans: [ShoppingPlan], mode: ShoppingMode = .cheaper, selectedID: UUID? = nil, origin: ShoppingCoordinate, isSaved: Bool,
          routeOptions: ShoppingRouteOptions = .init(), originAddress: String? = nil, startsAtSummary: Bool = false) {
        guard let first = plans.first else { return nil }
        self.plans = Array(plans.prefix(3))
        self.mode = mode
        self.selectedID = self.plans.first { $0.id == selectedID }?.id ?? first.id
        self.origin = origin
        self.originAddress = originAddress
        self.isSaved = isSaved
        self.routeOptions = routeOptions
        self.startsAtSummary = startsAtSummary
    }
}

extension ShoppingMode {
    func plans(in result: ShoppingPlanResult) -> [ShoppingPlan] {
        switch self {
        case .cheaper: result.plans
        case .faster: result.fastestPlans ?? []
        }
    }
}
