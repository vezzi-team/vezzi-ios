import Foundation

nonisolated protocol ShoppingListService: Sendable {
    func activeCart() async throws -> ShoppingCart?
    func cart(id: UUID) async throws -> ShoppingCart
    func createCart(name: String) async throws -> ShoppingCart
    func updateItem(cartID: UUID, productID: String, quantity: Int, exists: Bool) async throws -> ShoppingCart
    func plans(cartID: UUID, start: ShoppingCoordinate) async throws -> ShoppingPlanResult
}
