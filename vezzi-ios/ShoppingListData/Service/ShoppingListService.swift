import Foundation

nonisolated protocol ShoppingListService: Sendable {
    func activeCart() async throws -> ShoppingCart?
    func cart(id: UUID) async throws -> ShoppingCart
    func createCart(name: String) async throws -> ShoppingCart
    func updateItem(cartID: UUID, productID: String, quantity: Int, exists: Bool) async throws -> ShoppingCart
    func plans(cartID: UUID, start: ShoppingCoordinate, options: ShoppingRouteOptions) async throws -> ShoppingPlanResult
}

nonisolated protocol ShoppingProgressService: Sendable {
    func activePlan(cartID: UUID) async throws -> ShoppingPlan?
    func startPlan(id: UUID, cartID: UUID) async throws -> ShoppingPlan
    func updatePlanItem(planID: UUID, cartID: UUID, itemID: Int64, status: ShoppingItemStatus) async throws -> ShoppingPlan
    /// Returns the kept cart, or nil if the completed plan's cart has been deleted.
    func finishPlan(id: UUID, cartID: UUID, list: ShoppingTrip.ListDisposition, resuming: Bool) async throws -> ShoppingCart?
}
