import Foundation

/// A presentation snapshot remains valid while the list refreshes in the background.
nonisolated struct ShoppingRoutesSnapshot: Identifiable {
    let id = UUID()
    let plans: [ShoppingPlan]
    let selectedID: UUID
    let origin: ShoppingCoordinate
    let originAddress: String?
    let isSaved: Bool
    let routeOptions: ShoppingRouteOptions

    init?(plans: [ShoppingPlan], selectedID: UUID, origin: ShoppingCoordinate, isSaved: Bool,
          routeOptions: ShoppingRouteOptions = .init(), originAddress: String? = nil) {
        guard !plans.isEmpty else { return nil }
        self.plans = Array(plans.prefix(3))
        self.selectedID = self.plans.contains { $0.id == selectedID } ? selectedID : self.plans[0].id
        self.origin = origin
        self.originAddress = originAddress
        self.isSaved = isSaved
        self.routeOptions = routeOptions
    }
}
