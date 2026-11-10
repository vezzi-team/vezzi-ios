import Foundation

/// All account requests share authentication and token rotation with the catalog.
nonisolated struct APIShoppingListService: ShoppingListService {
    let client: any AuthorizedRequestPerforming

    @concurrent func activeCart() async throws -> ShoppingCart? {
        let response = try await client.authorizedResponse(for: APIRequest(path: "carts", queryItems: [URLQueryItem(name: "status", value: "active")]))
        let summaries: [CartSummaryDTO] = try response.decode()
        guard let first = summaries.first else { return nil }
        return try await cart(id: first.id)
    }

    @concurrent func cart(id: UUID) async throws -> ShoppingCart {
        let response = try await client.authorizedResponse(for: APIRequest(path: "carts/\(id.uuidString)"))
        return try response.decode(CartDTO.self).record()
    }

    @concurrent func createCart(name: String) async throws -> ShoppingCart {
        let response = try await client.authorizedResponse(for: APIRequest(path: "carts", method: "POST", body: APIClient.encode(CartCreate(name: name))))
        return try response.decode(CartDTO.self).record()
    }

    @concurrent func updateItem(cartID: UUID, productID: String, quantity: Int, exists: Bool) async throws -> ShoppingCart {
        guard let id = Int64(productID), id > 0, (0...99).contains(quantity) else { throw APIError.invalidResponse }
        let path = "carts/\(cartID.uuidString)/items"
        let request: APIRequest
        if quantity == 0 {
            request = APIRequest(path: "\(path)/\(id)", method: "DELETE")
        } else if exists {
            request = APIRequest(path: "\(path)/\(id)", method: "PATCH", body: try APIClient.encode(ItemUpdate(quantity: quantity)))
        } else {
            request = APIRequest(path: path, method: "POST", body: try APIClient.encode(ItemAdd(productId: id, quantity: quantity)))
        }
        let response = try await client.authorizedResponse(for: request)
        return try response.decode(CartDTO.self).record()
    }

    @concurrent func plans(cartID: UUID, start: ShoppingCoordinate) async throws -> ShoppingPlanResult {
        let response = try await client.authorizedResponse(for: APIRequest(path: "carts/\(cartID.uuidString)/plans", method: "POST",
                                                                         body: APIClient.encode(PlanRequest(start: start))))
        let result: PlanResponseDTO = try response.decode()
        guard ["ok", "no_plans"].contains(result.status),
              (result.status == "ok") == !result.plans.isEmpty,
              Set(result.plans.map(\.id)).count == result.plans.count,
              result.baseline.map({ $0.totalKopecks >= 0 }) ?? true else { throw APIError.invalidResponse }
        return ShoppingPlanResult(plans: try result.plans.map { try $0.record() }, baselinePrice: result.baseline.map { Decimal($0.totalKopecks) / 100 },
                                  problem: result.problem?.reason, isSynthetic: result.dataIsSynthetic)
    }

    private struct CartCreate: Encodable { let name: String }
    private struct ItemAdd: Encodable { let productId: Int64; let quantity: Int }
    private struct ItemUpdate: Encodable { let quantity: Int }
    private struct PlanRequest: Encodable {
        let start: ShoppingCoordinate
        let maxStores = 3
        let maxTotalMinutes = 60
    }
    private struct CartSummaryDTO: Decodable, Sendable { let id: UUID }
    private struct CartDTO: Decodable, Sendable {
        let id: UUID
        let name: String
        let status: String
        let items: [CartItemDTO]

        func record() throws -> ShoppingCart {
            guard items.count <= 30, Set(items.map { $0.product.id }).count == items.count,
                  items.allSatisfy({ (1...99).contains($0.quantity) }) else { throw APIError.invalidResponse }
            return ShoppingCart(id: id, name: name, status: status,
                                items: items.map { ShoppingCartItem(product: $0.product.record, quantity: $0.quantity) })
        }
    }
    private struct CartItemDTO: Decodable, Sendable {
        let product: CatalogProductDTO
        let quantity: Int
    }
    private struct PlanResponseDTO: Decodable, Sendable {
        let status: String
        let plans: [PlanDTO]
        let baseline: BaselineDTO?
        let problem: ProblemDTO?
        let dataIsSynthetic: Bool
    }
    private struct BaselineDTO: Decodable, Sendable { let totalKopecks: Int64 }
    private struct ProblemDTO: Decodable, Sendable { let reason: String }
    private struct PlanDTO: Decodable, Sendable {
        let id: UUID
        let totalKopecks: Int64
        let savingsKopecks: Int64?
        let totalSeconds: Int
        let walkingMeters: Int
        let stops: [StopDTO]
        let route: RouteDTO
        let dataIsSynthetic: Bool

        func record() throws -> ShoppingPlan {
            let items = stops.flatMap(\.items)
            guard totalKopecks >= 0, totalSeconds >= 0, walkingMeters >= 0, !stops.isEmpty,
                  Set(stops.map { $0.store.id }).count == stops.count,
                  Set(items.map { $0.product.id }).count == items.count,
                  items.allSatisfy({ (1...99).contains($0.quantity) && $0.unitPriceKopecks >= 0 }),
                  stops.allSatisfy({ $0.position > 0 && $0.subtotalKopecks >= 0
                      && (-90...90).contains($0.store.latitude) && (-180...180).contains($0.store.longitude) }),
                  route.points.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
            else { throw APIError.invalidResponse }
            return ShoppingPlan(id: id, total: Decimal(totalKopecks) / 100, savings: savingsKopecks.map { Decimal($0) / 100 },
                         totalSeconds: totalSeconds, walkingMeters: walkingMeters,
                         stops: stops.sorted { $0.position < $1.position }.map(\.record), points: route.points,
                         usesRoadNetwork: route.usesRoadNetwork, isSynthetic: dataIsSynthetic)
        }
    }
    private struct RouteDTO: Decodable, Sendable {
        let points: [ShoppingCoordinate]
        let usesRoadNetwork: Bool
    }
    private struct StopDTO: Decodable, Sendable {
        let position: Int
        let store: CatalogStoreDTO
        let items: [PlanItemDTO]
        let subtotalKopecks: Int64

        var record: ShoppingPlanStop {
            ShoppingPlanStop(position: position, store: store.record, items: items.map(\.record), subtotal: Decimal(subtotalKopecks) / 100)
        }
    }
    private struct PlanItemDTO: Decodable, Sendable {
        let product: CatalogProductDTO
        let quantity: Int
        let unitPriceKopecks: Int64
        let cardPriceKopecks: Int64?
        let priceConditions: String?

        var record: ShoppingPlanItem {
            ShoppingPlanItem(product: product.record, quantity: quantity, unitPrice: Decimal(unitPriceKopecks) / 100,
                             cardPrice: cardPriceKopecks.map { Decimal($0) / 100 }, priceConditions: priceConditions)
        }
    }
}
