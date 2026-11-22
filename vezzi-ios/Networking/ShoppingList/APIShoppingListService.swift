import Foundation

/// Cart and planning requests use the signed-in account's session.
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

    @concurrent func plans(cartID: UUID, start: ShoppingCoordinate, options: ShoppingRouteOptions) async throws -> ShoppingPlanResult {
        guard start.isValid, options.isValid else { throw APIError.invalidResponse }
        let response = try await client.authorizedResponse(for: APIRequest(path: "carts/\(cartID.uuidString)/plans", method: "POST",
                                                                         body: APIClient.encode(PlanRequest(start: start, returnToStart: options.returnToStart,
                                                                                                          radiusMeters: options.radiusMeters))))
        let result: PlanResponseDTO = try response.decode()
        guard ["ok", "no_plans"].contains(result.status),
              (result.status == "ok") == !result.plans.isEmpty,
              result.baseline.map({ $0.totalKopecks >= 0 }) ?? true else { throw APIError.invalidResponse }
        let calculation = try ShoppingPlanResult(plans: result.plans.map { try $0.record() },
                                                 fastestPlans: result.fastestPlans.map { try $0.record() },
                                                 baselinePrice: result.baseline.map { Decimal($0.totalKopecks) / 100 },
                                                 problem: result.problem?.reason, isSynthetic: result.dataIsSynthetic,
                                                 minRequiredRadiusMeters: result.problem?.minRequiredRadiusMeters)
        guard calculation.hasValidRankings else { throw APIError.invalidResponse }
        return calculation
    }

    private struct CartCreate: Encodable { let name: String }
    private struct ItemAdd: Encodable { let productId: Int64; let quantity: Int }
    private struct ItemUpdate: Encodable { let quantity: Int }
    private struct PlanRequest: Encodable {
        let start: ShoppingCoordinate
        let maxStores = 3
        let maxTotalMinutes = 60
        let returnToStart: Bool
        let radiusMeters: Int?
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
        let fastestPlans: [PlanDTO]
        let baseline: BaselineDTO?
        let problem: ProblemDTO?
        let dataIsSynthetic: Bool
    }
    private struct BaselineDTO: Decodable, Sendable { let totalKopecks: Int64 }
    private struct ProblemDTO: Decodable, Sendable {
        let reason: String
        let minRequiredRadiusMeters: Int?
    }
    private struct PlanDTO: Decodable, Sendable {
        let id: UUID
        let cartId: UUID?
        let status: String?
        let totalKopecks: Int64
        let savingsKopecks: Int64?
        let totalSeconds: Int
        let walkingMeters: Int
        let returnWalkSeconds: Int?
        let returnWalkMeters: Int?
        let stops: [StopDTO]
        let route: RouteDTO
        let dataIsSynthetic: Bool

        func record() throws -> ShoppingPlan {
            let items = stops.flatMap(\.items)
            guard totalKopecks >= 0, totalSeconds >= 0, walkingMeters >= 0, !stops.isEmpty,
                  returnWalkSeconds.map({ $0 >= 0 }) ?? true, returnWalkMeters.map({ $0 >= 0 }) ?? true,
                  Set(stops.map { $0.store.id }).count == stops.count,
                  Set(items.map { $0.product.id }).count == items.count,
                  items.allSatisfy({ (1...99).contains($0.quantity) && $0.unitPriceKopecks >= 0 }),
                  stops.allSatisfy({ $0.position > 0 && $0.subtotalKopecks >= 0
                      && ($0.walkFromPreviousSeconds.map { $0 >= 0 } ?? true)
                      && ($0.walkFromPreviousMeters.map { $0 >= 0 } ?? true)
                      && (-90...90).contains($0.store.latitude) && (-180...180).contains($0.store.longitude) }),
                  route.points.allSatisfy({ (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) })
            else { throw APIError.invalidResponse }
            return ShoppingPlan(id: id, total: Decimal(totalKopecks) / 100, savings: savingsKopecks.map { Decimal($0) / 100 },
                         totalSeconds: totalSeconds, walkingMeters: walkingMeters,
                         stops: stops.sorted { $0.position < $1.position }.map(\.record), points: route.points,
                         usesRoadNetwork: route.usesRoadNetwork, isSynthetic: dataIsSynthetic,
                         returnWalkingSeconds: returnWalkSeconds, returnWalkingMeters: returnWalkMeters)
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
        let walkFromPreviousSeconds: Int?
        let walkFromPreviousMeters: Int?

        var record: ShoppingPlanStop {
            ShoppingPlanStop(position: position, store: store.record, items: items.map(\.record), subtotal: Decimal(subtotalKopecks) / 100,
                             walkingSeconds: walkFromPreviousSeconds, walkingMeters: walkFromPreviousMeters)
        }
    }
    private struct PlanItemDTO: Decodable, Sendable {
        let id: Int64?
        let status: ShoppingItemStatus?
        let product: CatalogProductDTO
        let quantity: Int
        let unitPriceKopecks: Int64
        let cardPriceKopecks: Int64?
        let priceConditions: String?

        var record: ShoppingPlanItem {
            ShoppingPlanItem(product: product.record, quantity: quantity, unitPrice: Decimal(unitPriceKopecks) / 100,
                             cardPrice: cardPriceKopecks.map { Decimal($0) / 100 }, priceConditions: priceConditions,
                             itemID: id, status: status)
        }
    }
}

extension APIShoppingListService: ShoppingProgressService {
    private struct Summary: Decodable { let id: UUID; let cartId: UUID? }
    private struct ItemStatusUpdate: Encodable { let status: ShoppingItemStatus }

    @concurrent func activePlan(cartID: UUID) async throws -> ShoppingPlan? {
        let response = try await client.authorizedResponse(for: APIRequest(path: "plans", queryItems: [.init(name: "status", value: "active")]))
        let summaries: [Summary] = try response.decode()
        guard let match = summaries.first(where: { $0.cartId == cartID }) else { return nil }
        return try await readPlan(APIRequest(path: "plans/\(match.id.uuidString)"), id: match.id, cartID: cartID)
    }

    @concurrent func startPlan(id: UUID, cartID: UUID) async throws -> ShoppingPlan {
        try await readPlan(APIRequest(path: "plans/\(id.uuidString)/start", method: "POST"), id: id, cartID: cartID)
    }

    @concurrent func updatePlanItem(planID: UUID, cartID: UUID, itemID: Int64, status: ShoppingItemStatus) async throws -> ShoppingPlan {
        let request = APIRequest(path: "plans/\(planID.uuidString)/items/\(itemID)", method: "PATCH",
                                 body: try APIClient.encode(ItemStatusUpdate(status: status)))
        return try await readPlan(request, id: planID, cartID: cartID)
    }

    private struct CompletionState: Decodable { let id: UUID; let cartId: UUID?; let status: String }
    private struct CartStatus: Encodable { let status: String }

    @concurrent func finishPlan(id: UUID, cartID: UUID, list: ShoppingTrip.ListDisposition, resuming: Bool) async throws -> ShoppingCart? {
        let path = "plans/\(id.uuidString)"
        var completed = false
        if resuming {
            let response = try await client.authorizedResponse(for: APIRequest(path: path))
            let state: CompletionState = try response.decode()
            guard state.id == id, ["completed", "active"].contains(state.status) else { throw APIError.invalidResponse }
            completed = state.status == "completed"
            if completed && state.cartId == nil { return nil }
            guard state.cartId == cartID else { throw APIError.invalidResponse }
        }
        if !completed {
            _ = try await readPlan(APIRequest(path: path + "/complete", method: "POST"), id: id, cartID: cartID, expectedStatus: "completed")
        }
        let cartPath = "carts/\(cartID.uuidString)"
        switch list {
        case .delete:
            do { _ = try await client.authorizedResponse(for: APIRequest(path: cartPath, method: "DELETE")) }
            catch where (error as? APIError)?.status == 404 { }
            return nil
        case .keep:
            let request = APIRequest(path: cartPath, method: "PATCH", body: try APIClient.encode(CartStatus(status: "active")))
            let response: APIResponse
            do { response = try await client.authorizedResponse(for: request) }
            catch let error as APIError where error.status == 404 { return nil }
            let restored = try response.decode(CartDTO.self).record()
            guard restored.id == cartID, restored.status == "active" else { throw APIError.invalidResponse }
            return restored
        }
    }

    private func readPlan(_ request: APIRequest, id: UUID, cartID: UUID, expectedStatus: String = "active") async throws -> ShoppingPlan {
        let response = try await client.authorizedResponse(for: request)
        let dto: PlanDTO = try response.decode()
        let items = dto.stops.flatMap(\.items)
        guard dto.id == id, dto.cartId == cartID, dto.status == expectedStatus,
              !items.isEmpty, items.allSatisfy({ ($0.id ?? 0) > 0 && $0.status != nil }),
              Set(items.compactMap(\.id)).count == items.count else { throw APIError.invalidResponse }
        return try dto.record()
    }
}
