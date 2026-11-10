import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingListAPITests: XCTestCase {
    private let cartID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    func testActiveCartUsesAuthorizedRequestsAndRestoresProductData() async throws {
        let client = ShoppingRequestStub(responses: [try json([["id": cartID.uuidString]]), try json(cart())])
        let result = try await APIShoppingListService(client: client).activeCart()
        XCTAssertEqual(result?.quantities, ["1": 2])
        XCTAssertEqual(result?.items.first?.product.packageQuantity, Decimal(string: "930.5"))
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.path), ["carts", "carts/\(cartID.uuidString)"])
        XCTAssertEqual(requests[0].queryItems, [URLQueryItem(name: "status", value: "active")])
    }

    func testQuantityRequestsUseAddOnlyForNewItemsAndAbsolutePatchForExistingItems() async throws {
        let client = ShoppingRequestStub(responses: Array(repeating: try json(cart()), count: 3))
        let service = APIShoppingListService(client: client)
        _ = try await service.updateItem(cartID: cartID, productID: "1", quantity: 2, exists: false)
        _ = try await service.updateItem(cartID: cartID, productID: "1", quantity: 5, exists: true)
        _ = try await service.updateItem(cartID: cartID, productID: "1", quantity: 0, exists: true)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["POST", "PATCH", "DELETE"])
        XCTAssertEqual(requests.map(\.path), ["carts/\(cartID.uuidString)/items", "carts/\(cartID.uuidString)/items/1", "carts/\(cartID.uuidString)/items/1"])
        let add = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].body)) as? [String: Int])
        let patch = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].body)) as? [String: Int])
        XCTAssertEqual(add, ["product_id": 1, "quantity": 2])
        XCTAssertEqual(patch, ["quantity": 5])
        XCTAssertNil(requests[2].body)
    }

    func testPlansDecodeKopecksExactlyAndPreserveRouteProvenance() async throws {
        let client = ShoppingRequestStub(responses: [try json(plans())])
        let result = try await APIShoppingListService(client: client).plans(cartID: cartID, start: .previewOrigin)
        let plan = try XCTUnwrap(result.plans.first)
        XCTAssertEqual(plan.total, Decimal(string: "199.98"))
        XCTAssertEqual(plan.stops.first?.items.first?.unitPrice, Decimal(string: "99.99"))
        XCTAssertEqual(plan.stops.first?.items.first?.cardPrice, Decimal(string: "89.99"))
        XCTAssertEqual(result.baselinePrice, Decimal(string: "210.10"))
        XCTAssertTrue(result.isSynthetic)
        XCTAssertFalse(plan.usesRoadNetwork)
        XCTAssertEqual(plan.points, [.previewOrigin])
        let firstRequest = await client.firstRequest()
        let request = try XCTUnwrap(firstRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["max_stores"] as? Int, 3)
        XCTAssertEqual(body["max_total_minutes"] as? Int, 60)
        XCTAssertNotNil(body["start"])
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "carts/\(cartID.uuidString)/plans")
    }

    func testInvalidCartAndRouteAreRejected() async throws {
        var duplicate = cart()
        let items = try XCTUnwrap(duplicate["items"] as? [[String: Any]])
        duplicate["items"] = items + items
        let client = ShoppingRequestStub(responses: [try json(duplicate)])
        do {
            _ = try await APIShoppingListService(client: client).cart(id: cartID)
            XCTFail("Duplicate products must not reach dictionary-based state")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        var invalid = plans()
        var values = try XCTUnwrap(invalid["plans"] as? [[String: Any]])
        values[0]["route"] = ["uses_road_network": true, "points": [["latitude": 1000, "longitude": 30]]]
        invalid["plans"] = values
        let badRoute = ShoppingRequestStub(responses: [try json(invalid)])
        do {
            _ = try await APIShoppingListService(client: badRoute).plans(cartID: cartID, start: .previewOrigin)
            XCTFail("Invalid coordinates must not reach MapKit")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }

    func testNoPlansIsAValidResponseAndInvalidProductIDNeverReachesTransport() async throws {
        let client = ShoppingRequestStub(responses: [try json(["status": "no_plans", "plans": [], "baseline": NSNull(),
                                                             "problem": ["reason": "items_unavailable"], "data_is_synthetic": false])])
        let service = APIShoppingListService(client: client)
        let result = try await service.plans(cartID: cartID, start: .previewOrigin)
        XCTAssertEqual(result.problem, "items_unavailable")
        XCTAssertTrue(result.plans.isEmpty)
        do {
            _ = try await service.updateItem(cartID: cartID, productID: "../other", quantity: 1, exists: false)
            XCTFail("Invalid product identifiers must not be sent")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        let count = await client.requests.count
        XCTAssertEqual(count, 1)
    }

    private func product() -> [String: Any] {
        ["id": 1, "name": "Milk", "brand": "Brand", "category": "Dairy", "product_type": "milk",
         "package_amount": 930.5, "package_unit": "ml"]
    }
    private func cart() -> [String: Any] {
        ["id": cartID.uuidString, "name": "List", "status": "active", "items": [["product": product(), "quantity": 2]]]
    }
    private func plans() -> [String: Any] {
        let item: [String: Any] = ["product": product(), "quantity": 2, "unit_price_kopecks": 9999, "card_price_kopecks": 8999,
                                  "price_conditions": "Loyalty card"]
        let store: [String: Any] = ["id": 1, "chain": "Chain", "name": "Branch", "address": "Saint Petersburg, Street 1",
                                   "latitude": 60.01, "longitude": 30.26, "format": "supermarket"]
        let plan: [String: Any] = ["id": UUID().uuidString, "total_kopecks": 19998, "savings_kopecks": 1012, "total_seconds": 600,
                                  "walking_meters": 800, "data_is_synthetic": true,
                                  "stops": [["position": 1, "store": store, "items": [item], "subtotal_kopecks": 19998]],
                                  "route": ["uses_road_network": false, "points": [["latitude": 60.0087, "longitude": 30.2582]]]]
        return ["status": "ok", "plans": [plan], "baseline": ["total_kopecks": 21010], "problem": NSNull(), "data_is_synthetic": true]
    }
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
}

private actor ShoppingRequestStub: AuthorizedRequestPerforming {
    private var responses: [Data]
    private(set) var requests: [APIRequest] = []
    init(responses: [Data]) { self.responses = responses }
    func firstRequest() -> APIRequest? { requests.first }
    func authorizedResponse(for request: APIRequest) throws -> APIResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw APIError.invalidResponse }
        return APIResponse(data: responses.removeFirst(), status: 200, etag: nil)
    }
}
