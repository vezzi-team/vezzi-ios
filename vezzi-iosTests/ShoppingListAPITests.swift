import Combine
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
        let result = try await APIShoppingListService(client: client).plans(cartID: cartID, start: .previewOrigin, options: .init())
        let plan = try XCTUnwrap(result.plans.first)
        XCTAssertEqual(plan.total, Decimal(string: "199.98"))
        XCTAssertEqual(plan.stops.first?.items.first?.unitPrice, Decimal(string: "99.99"))
        XCTAssertEqual(plan.stops.first?.items.first?.cardPrice, Decimal(string: "89.99"))
        XCTAssertEqual(result.baselinePrice, Decimal(string: "210.10"))
        XCTAssertTrue(result.isSynthetic)
        XCTAssertFalse(plan.usesRoadNetwork)
        XCTAssertEqual(plan.stops.first?.walkingSeconds, 240)
        XCTAssertEqual(plan.stops.first?.walkingMeters, 350)
        XCTAssertEqual(plan.points, [.previewOrigin])
        let firstRequest = await client.firstRequest()
        let request = try XCTUnwrap(firstRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["max_stores"] as? Int, 3)
        XCTAssertEqual(body["max_total_minutes"] as? Int, 60)
        XCTAssertNotNil(body["start"])
        XCTAssertEqual(body["return_to_start"] as? Bool, false)
        XCTAssertNil(body["radius_meters"])
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "carts/\(cartID.uuidString)/plans")
    }

    func testFastestRankingPreservesServerOrderAndMayOverlapPriceRanking() async throws {
        var response = plans()
        let cheap = try XCTUnwrap((response["plans"] as? [[String: Any]])?.first)
        let fastID = UUID()
        var fast = cheap
        fast["id"] = fastID.uuidString
        fast["total_seconds"] = 350
        fast["total_kopecks"] = 31000
        response["fastest_plans"] = [fast, cheap]
        let client = ShoppingRequestStub(responses: [try json(response)])
        let result = try await APIShoppingListService(client: client).plans(cartID: cartID, start: .defaultOrigin, options: .init())
        let cheapPlan = try XCTUnwrap(result.plans.first)
        XCTAssertEqual(result.fastestPlans?.map(\.id), [fastID, cheapPlan.id])
        XCTAssertEqual(result.fastestPlans?.first?.total, 310)
        XCTAssertEqual(result.fastestPlans?.first?.totalSeconds, 350)
    }

    func testInvalidFastestRankingIsRejectedIndependentlyOfPriceRanking() async throws {
        var response = plans()
        let plan = try XCTUnwrap((response["plans"] as? [[String: Any]])?.first)
        var invalid = plan
        invalid["total_seconds"] = -1
        for ranking in [[], [invalid], [plan, plan]] {
            response["fastest_plans"] = ranking
            let service = APIShoppingListService(client: ShoppingRequestStub(responses: [try json(response)]))
            do {
                _ = try await service.plans(cartID: cartID, start: .defaultOrigin, options: .init())
                XCTFail("Expected an invalid fastest ranking to be rejected")
            } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        }
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
            _ = try await APIShoppingListService(client: badRoute).plans(cartID: cartID, start: .previewOrigin, options: .init())
            XCTFail("Invalid coordinates must not reach MapKit")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }

    func testNoPlansIsAValidResponseAndInvalidProductIDNeverReachesTransport() async throws {
        let client = ShoppingRequestStub(responses: [try json(["status": "no_plans", "plans": [], "fastest_plans": [], "baseline": NSNull(),
                                                             "problem": ["reason": "items_unavailable"], "data_is_synthetic": false])])
        let service = APIShoppingListService(client: client)
        let result = try await service.plans(cartID: cartID, start: .previewOrigin, options: .init())
        XCTAssertEqual(result.problem, "items_unavailable")
        XCTAssertTrue(result.plans.isEmpty)
        XCTAssertEqual(result.fastestPlans?.count, 0)
        do {
            _ = try await service.updateItem(cartID: cartID, productID: "../other", quantity: 1, exists: false)
            XCTFail("Invalid product identifiers must not be sent")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        let count = await client.requests.count
        XCTAssertEqual(count, 1)
    }

    func testRouteConstraintsAndReturnLegUseServerFieldNames() async throws {
        var response = plans()
        var values = try XCTUnwrap(response["plans"] as? [[String: Any]])
        values[0]["return_walk_seconds"] = 120
        values[0]["return_walk_meters"] = 160
        response["plans"] = values
        let client = ShoppingRequestStub(responses: [try json(response)])
        let options = ShoppingRouteOptions(returnToStart: true, radiusMeters: 750)
        let result = try await APIShoppingListService(client: client).plans(cartID: cartID, start: .previewOrigin, options: options)
        XCTAssertEqual(result.plans.first?.returnWalkingSeconds, 120)
        XCTAssertEqual(result.plans.first?.returnWalkingMeters, 160)
        let request = await client.firstRequest()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request?.body)) as? [String: Any])
        XCTAssertEqual(body["radius_meters"] as? Int, 750)
        XCTAssertEqual(body["return_to_start"] as? Bool, true)
    }

    func testRadiusFailurePreservesSuggestionAndInvalidRadiusDoesNotSendRequest() async throws {
        let client = ShoppingRequestStub(responses: [try json(["status": "no_plans", "plans": [], "fastest_plans": [], "baseline": NSNull(),
            "problem": ["reason": "radius_too_small", "min_required_radius_meters": 1275], "data_is_synthetic": false])])
        let service = APIShoppingListService(client: client)
        let result = try await service.plans(cartID: cartID, start: .previewOrigin, options: .init(radiusMeters: 500))
        XCTAssertEqual(result.problem, "radius_too_small")
        XCTAssertEqual(result.minRequiredRadiusMeters, 1275)
        for radius in [99, 5001] {
            do {
                _ = try await service.plans(cartID: cartID, start: .previewOrigin, options: .init(radiusMeters: radius))
                XCTFail("Invalid constraints must not be sent")
            } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
        }
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
                                  "stops": [["position": 1, "store": store, "items": [item], "subtotal_kopecks": 19998,
                                             "walk_from_previous_seconds": 240, "walk_from_previous_meters": 350]],
                                  "route": ["uses_road_network": false, "points": [["latitude": 60.0087, "longitude": 30.2582]]]]
        return ["status": "ok", "plans": [plan], "fastest_plans": [plan], "baseline": ["total_kopecks": 21010],
                "problem": NSNull(), "data_is_synthetic": true]
    }
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
}

private actor ShoppingRequestStub: AuthorizedRequestPerforming {
    private var responses: [Data]
    private(set) var requests: [APIRequest] = []
    private var offline = false
    private var patchError: APIError?
    private var onNextPatch: (@Sendable () async -> Void)?

    init(responses: [Data]) { self.responses = responses }
    func setOffline(_ offline: Bool) { self.offline = offline }
    func rejectNextPatch(_ error: APIError) { patchError = error }
    func pauseNextPatch(_ pause: @escaping @Sendable () async -> Void) { onNextPatch = pause }
    func firstRequest() -> APIRequest? { requests.first }
    func authorizedResponse(for request: APIRequest) async throws -> APIResponse {
        requests.append(request)
        guard !offline else { throw URLError(.notConnectedToInternet) }
        if request.method == "PATCH", let patchError {
            self.patchError = nil
            throw patchError
        }
        if request.method == "PATCH", let pause = onNextPatch {
            onNextPatch = nil
            await pause()
        }
        guard !responses.isEmpty else { throw APIError.invalidResponse }
        return APIResponse(data: responses.removeFirst(), status: 200, etag: nil)
    }
}

extension ShoppingListAPITests {
    func testResumingFinishAfterCompletionKeepsTheSameCartWithoutCompletingTwice() async throws {
        let id = UUID()
        let state = ["id": id.uuidString, "cart_id": cartID.uuidString, "status": "completed"]
        let client = ShoppingRequestStub(responses: [try json(state), try json(cart())])
        let result = try await APIShoppingListService(client: client).finishPlan(id: id, cartID: cartID, list: .keep, resuming: true)
        XCTAssertEqual(result?.id, cartID)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "PATCH"])
        XCTAssertEqual(requests.last?.path, "carts/\(cartID.uuidString)")
        let body = try XCTUnwrap(requests.last?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["status": "active"])
    }

    @MainActor
    func testRelaunchFinishesSavedChoiceBeforeLookingForAnActiveCart() async throws {
        let fixture = ShoppingListPreview.repository()
        let account = ShoppingListPreview.account
        fixture.setAccount(account)
        fixture.setPresented(true)
        await fixture.refresh()
        let id = try XCTUnwrap(fixture.planResult?.plans.first?.id)
        _ = await fixture.startTrip(id)
        var trip = try XCTUnwrap(fixture.trip)
        trip.pendingFinish = .delete
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileShoppingListCache(directory: directory)
        try await cache.save(.init(cart: fixture.cart, pending: [:], plan: nil, trip: trip), account: account)

        // The DELETE reached the server, but the process quit before recording success.
        let client = ShoppingRequestStub(responses: [try json(["id": id.uuidString, "status": "completed"]), try json([])])
        let restored = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        restored.setAccount(account)
        await restored.refresh()
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.path), ["plans/\(id.uuidString)", "carts"])
        XCTAssertNil(restored.trip)
        let saved = try await cache.load(account: account)
        XCTAssertNil(saved?.trip)
        XCTAssertTrue(restored.hasResolvedCart)
    }

    func testResumingDeleteAfterLostResponseLeavesOtherListsAlone() async throws {
        let id = UUID()
        let client = ShoppingRequestStub(responses: [try json(["id": id.uuidString, "status": "completed"])])
        let result = try await APIShoppingListService(client: client).finishPlan(id: id, cartID: cartID, list: .delete, resuming: true)
        XCTAssertNil(result)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET"])
    }

    private func purchaseResponse(id: UUID, itemStatus: ShoppingItemStatus, secondStatus: ShoppingItemStatus? = nil, completed: Bool = false) throws -> Data {
        var record = try XCTUnwrap((plans()["plans"] as? [[String: Any]])?.first)
        record["id"] = id.uuidString
        record["cart_id"] = cartID.uuidString
        record["status"] = completed ? "completed" : "active"
        var stops = try XCTUnwrap(record["stops"] as? [[String: Any]])
        var items = try XCTUnwrap(stops[0]["items"] as? [[String: Any]])
        items[0]["id"] = 712
        items[0]["status"] = itemStatus.rawValue
        if let secondStatus {
            var second = items[0]
            second["id"] = 713
            second["product"] = product().merging(["id": 2, "name": "Bread"]) { _, new in new }
            second["status"] = secondStatus.rawValue
            items.append(second)
            stops[0]["subtotal_kopecks"] = 39996
            record["total_kopecks"] = 39996
        }
        stops[0]["items"] = items
        record["stops"] = stops
        return try json(record)
    }

    private func restoreResponses(planID: UUID) throws -> [Data] {
        try [json([["id": cartID.uuidString]]), json(cart()),
             json([["id": planID.uuidString, "cart_id": cartID.uuidString]]), purchaseResponse(id: planID, itemStatus: .planned)]
    }

    func testOfflineCheckAndUncheckSurviveRestartsAndReconnectFlushesBeforeFinish() async throws {
        let id = UUID()
        let account = ShoppingListPreview.account
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileShoppingListCache(directory: directory)
        let active = try purchaseResponse(id: id, itemStatus: .planned)
        let completion = try purchaseResponse(id: id, itemStatus: .planned, completed: true)
        let client = ShoppingRequestStub(responses: try restoreResponses(planID: id) + [active, active, completion, Data(), json([])])
        let service = APIShoppingListService(client: client)

        func launch() async -> ShoppingListRepository {
            let list = ShoppingListRepository(service: service, cache: cache)
            list.setAccount(account)
            await list.refresh()
            return list
        }

        let first = await launch()
        await client.setOffline(true)
        first.updateConnectivity(isConnected: false)
        XCTAssertTrue(first.togglePurchase(itemID: 712, planID: id))
        XCTAssertEqual(first.trip?.spent, Decimal(string: "199.98"))
        await first.refresh()
        XCTAssertEqual(first.failure, .offline)
        XCTAssertNil(first.tripFailure)

        let second = await launch()
        XCTAssertEqual(second.trip?.boughtCount, 1)
        XCTAssertTrue(second.togglePurchase(itemID: 712, planID: id))
        XCTAssertEqual(second.trip?.spent, 0)
        let finishedOffline = await second.finishShopping(.delete)
        XCTAssertFalse(finishedOffline)
        XCTAssertFalse(second.togglePurchase(itemID: 712, planID: id))
        await second.refresh()

        let restarted = await launch()
        XCTAssertEqual(restarted.trip?.boughtCount, 0)
        XCTAssertEqual(restarted.trip?.pendingMarks, [712: .planned])
        XCTAssertEqual(restarted.trip?.pendingFinish, .delete)
        let offlineRequests = await client.requests
        XCTAssertFalse(offlineRequests.contains { $0.path.hasSuffix("/complete") || $0.method == "DELETE" })

        restarted.updateConnectivity(isConnected: false)
        await client.setOffline(false)
        let synchronized = expectation(description: "Connectivity alone synchronizes the restored trip")
        let observation = restarted.$isBusy.dropFirst().filter { !$0 }.first().sink { _ in synchronized.fulfill() }
        restarted.updateConnectivity(isConnected: true)
        await fulfillment(of: [synchronized], timeout: 5)
        observation.cancel()
        let sent = await client.requests.dropFirst(offlineRequests.count)
        XCTAssertEqual(sent.map(\.method), ["PATCH", "GET", "POST", "DELETE", "GET"])
        XCTAssertEqual(sent.first?.path, "plans/\(id.uuidString)/items/712")
        let body = try XCTUnwrap(sent.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["status": "planned"])
        XCTAssertNil(restarted.trip)
        let saved = try await cache.load(account: account)
        XCTAssertNil(saved?.trip)
    }

    func testReconnectSyncsLatestMarksForMultipleItemsWithoutFinishing() async throws {
        let id = UUID()
        let planned = try purchaseResponse(id: id, itemStatus: .planned, secondStatus: .planned)
        let partial = try purchaseResponse(id: id, itemStatus: .bought, secondStatus: .planned)
        let both = try purchaseResponse(id: id, itemStatus: .bought, secondStatus: .bought)
        let summary = try json([["id": id.uuidString, "cart_id": cartID.uuidString]])
        var activeCart = cart()
        activeCart["items"] = [product(), product().merging(["id": 2, "name": "Bread"]) { _, new in new }].map {
            ["product": $0, "quantity": 2]
        }
        let cartData = try json(activeCart)
        let client = ShoppingRequestStub(responses: try [json([["id": cartID.uuidString]]), cartData, summary, planned,
                                                          partial, both, cartData, summary, both])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client))
        list.setAccount(ShoppingListPreview.account)
        await list.refresh()
        await client.setOffline(true)
        list.updateConnectivity(isConnected: false)
        for item in [712, 713, 712, 712] as [Int64] {
            XCTAssertTrue(list.togglePurchase(itemID: item, planID: id))
        }
        await list.refresh()
        XCTAssertEqual(list.trip?.boughtCount, 2)
        let requestCount = await client.requests.count
        var visibleCounts: [Int] = []
        let changes = list.$trip.compactMap { $0?.boughtCount }.sink { visibleCounts.append($0) }
        let synced = expectation(description: "Marks sync without a request to finish")
        let observation = list.$isBusy.dropFirst().filter { !$0 }.first().sink { _ in synced.fulfill() }
        await client.setOffline(false)
        list.updateConnectivity(isConnected: true)
        await fulfillment(of: [synced], timeout: 5)
        observation.cancel()
        changes.cancel()
        XCTAssertEqual(Set(visibleCounts), [2])
        XCTAssertEqual(list.trip?.plan.id, id)
        XCTAssertNil(list.trip?.pendingMarks)
        let mutations = await client.requests.dropFirst(requestCount).filter { $0.method != "GET" }
        XCTAssertEqual(mutations.map(\.path), ["plans/\(id.uuidString)/items/712", "plans/\(id.uuidString)/items/713"])
    }

    func testReplacedActiveTripDoesNotInheritOfflineMarksOrCompletion() async throws {
        let original = UUID()
        let replacement = UUID()
        let summary = try json([["id": replacement.uuidString, "cart_id": cartID.uuidString]])
        let client = ShoppingRequestStub(responses: try restoreResponses(planID: original) + [
            summary, purchaseResponse(id: replacement, itemStatus: .planned)
        ])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client))
        list.setAccount(ShoppingListPreview.account)
        await list.refresh()
        await client.rejectNextPatch(.http(status: 409, code: nil, requestID: nil, retryAfter: nil))
        XCTAssertTrue(list.togglePurchase(itemID: 712, planID: original))
        let finished = await list.finishShopping(.delete)
        XCTAssertFalse(finished)
        XCTAssertEqual(list.trip?.plan.id, replacement)
        XCTAssertEqual(list.trip?.boughtCount, 0)
        XCTAssertEqual(list.trip?.needsSync, false)
        XCTAssertEqual(list.tripFailure, .cartUnavailable)
        let mutations = await client.requests.filter { $0.method != "GET" }
        XCTAssertEqual(mutations.map(\.path), ["plans/\(original.uuidString)/items/712"])
    }

    func testUndoDuringPatchSurvivesLateReplyAndFinishesAfterLatestStatus() async throws {
        let id = UUID()
        let planned = try purchaseResponse(id: id, itemStatus: .planned)
        let bought = try purchaseResponse(id: id, itemStatus: .bought)
        let completed = try purchaseResponse(id: id, itemStatus: .planned, completed: true)
        let client = ShoppingRequestStub(responses: try restoreResponses(planID: id) + [bought, planned, planned, completed, Data(), json([])])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client))
        list.setAccount(ShoppingListPreview.account)
        await list.refresh()
        let started = expectation(description: "First PATCH in flight")
        let (gate, release) = AsyncStream<Void>.makeStream()
        await client.pauseNextPatch {
            started.fulfill()
            for await _ in gate { break }
        }
        XCTAssertTrue(list.togglePurchase(itemID: 712, planID: id))
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(list.togglePurchase(itemID: 712, planID: id))
        let undoWasOverwritten = expectation(description: "A stale PATCH must not restore the checkmark")
        undoWasOverwritten.isInverted = true
        let observation = list.$trip.sink { if $0?.boughtCount == 1 { undoWasOverwritten.fulfill() } }
        let confirmation = expectation(description: "Finish accepted before the first response")
        let pending = list.$trip.compactMap { $0?.pendingFinish }.first().sink { _ in confirmation.fulfill() }
        let finish = Task { await list.finishShopping(.delete) }
        await fulfillment(of: [confirmation], timeout: 5)
        release.finish()
        let success = await finish.value
        XCTAssertTrue(success)
        observation.cancel()
        pending.cancel()
        await fulfillment(of: [undoWasOverwritten], timeout: 0.05)
        let writes = await client.requests.filter { $0.method != "GET" }
        XCTAssertEqual(writes.map(\.method), ["PATCH", "PATCH", "POST", "DELETE"])
        let statuses = try writes.prefix(2).map {
            try JSONDecoder().decode([String: String].self, from: XCTUnwrap($0.body))["status"]
        }
        XCTAssertEqual(statuses, ["bought", "planned"])
    }

    func testPurchaseUsesPlanLineIDAndServerStatusAndValidatesCart() async throws {
        let id = UUID()
        let active = try purchaseResponse(id: id, itemStatus: .planned)
        let bought = try purchaseResponse(id: id, itemStatus: .bought)
        let completed = try purchaseResponse(id: id, itemStatus: .bought, completed: true)
        let summary = [["id": id.uuidString, "cart_id": cartID.uuidString]]
        let client = ShoppingRequestStub(responses: [try json(summary), active, active, bought, completed, Data(), active])
        let service = APIShoppingListService(client: client)
        let restored = try await service.activePlan(cartID: cartID)
        XCTAssertEqual(restored?.id, id)
        let started = try await service.startPlan(id: id, cartID: cartID)
        XCTAssertEqual(started.stops.first?.items.first?.itemID, 712)
        let updated = try await service.updatePlanItem(planID: id, cartID: cartID, itemID: 712, status: .bought)
        XCTAssertEqual(updated.stops.first?.spent, Decimal(string: "199.98"))
        let deleted = try await service.finishPlan(id: id, cartID: cartID, list: .delete, resuming: false)
        XCTAssertNil(deleted)
        let requests = await client.requests
        XCTAssertEqual(requests[0].queryItems.first?.value, "active")
        XCTAssertEqual(requests[2].path, "plans/\(id.uuidString)/start")
        XCTAssertEqual(requests[3].path, "plans/\(id.uuidString)/items/712")
        XCTAssertEqual(requests[3].method, "PATCH")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(requests[3].body)) as? [String: String], ["status": "bought"])
        XCTAssertEqual(requests[4].path, "plans/\(id.uuidString)/complete")
        XCTAssertEqual(requests[5].method, "DELETE")
        XCTAssertEqual(requests[5].path, "carts/\(cartID.uuidString)")
        do {
            _ = try await service.startPlan(id: id, cartID: UUID())
            XCTFail("Accepted a response for another cart")
        } catch { XCTAssertEqual(error as? APIError, .invalidResponse) }
    }
}

extension ShoppingListAPITests {
    private func savedTrip(id: UUID, finishing: ShoppingTrip.ListDisposition? = nil) async throws -> ShoppingListCacheSnapshot {
        let client = ShoppingRequestStub(responses: try restoreResponses(planID: id))
        let list = ShoppingListRepository(service: APIShoppingListService(client: client))
        list.setAccount(ShoppingListPreview.account)
        await list.refresh()
        var trip = try XCTUnwrap(list.trip)
        trip.page = .store(try XCTUnwrap(trip.plan.stops.first?.id))
        trip.pendingFinish = finishing
        return ShoppingListCacheSnapshot(cart: list.cart, pending: [:], plan: nil, trip: trip)
    }

    func testRelaunchPrefersTheCartOfTheSavedTripAndRestoresItsPage() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let account = ShoppingListPreview.account
        let id = UUID()
        let snapshot = try await savedTrip(id: id)
        try await cache.save(snapshot, account: account)
        let other = ["id": UUID().uuidString, "cart_id": UUID().uuidString]
        let original = ["id": id.uuidString, "cart_id": cartID.uuidString]
        let client = ShoppingRequestStub(responses: try [json(cart()), json([other, original]), purchaseResponse(id: id, itemStatus: .bought)])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        list.setAccount(account)
        await list.refresh()
        XCTAssertNil(list.failure)
        XCTAssertEqual(list.trip?.page, snapshot.trip?.page)
        XCTAssertEqual(list.trip?.boughtCount, 1)
        let persisted = try await cache.load(account: account)
        XCTAssertEqual(persisted?.trip?.plan.id, id)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.path), ["carts/\(cartID.uuidString)", "plans", "plans/\(id.uuidString)"])
    }

    func testRelaunchUsesLatestCartIfCachedTripIsNoLongerActive() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let account = ShoppingListPreview.account
        try await cache.save(savedTrip(id: UUID()), account: account)
        let otherID = UUID()
        var other = cart()
        other["id"] = otherID.uuidString
        let client = ShoppingRequestStub(responses: try [json(cart()), json([]), json([["id": otherID.uuidString]]), json(other), json([])])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        list.setAccount(account)
        await list.refresh()
        XCTAssertNil(list.failure)
        XCTAssertEqual(list.cart?.id, otherID)
        XCTAssertNil(list.trip)
        XCTAssertFalse(list.selection.isShopping)
    }

    func testCartIsAvailableIfTheInitialProgressRequestFails() async throws {
        let cache = MemoryShoppingListCache()
        let account = ShoppingListPreview.account
        let client = ShoppingRequestStub(responses: try [json([["id": cartID.uuidString]]), json(cart())])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        list.setAccount(account)
        await list.refresh()
        XCTAssertNotNil(list.failure)
        XCTAssertEqual(list.selection.quantities, ["1": 2])
        let snapshot = try await cache.load(account: account)
        XCTAssertEqual(snapshot?.cart?.id, cartID)
        XCTAssertEqual(snapshot?.hasResolvedCart, true)
        let requests = await client.requests
        XCTAssertTrue(requests.allSatisfy { $0.method == "GET" })
    }

    func testRecoveredCacheRestoresItsActiveTripAfterAnotherCartLoaded() async throws {
        let cache = MemoryShoppingListCache()
        let account = ShoppingListPreview.account
        let id = UUID()
        let snapshot = try await savedTrip(id: id)
        try await cache.save(snapshot, account: account)
        await cache.setFailing(true)
        let otherID = UUID()
        var other = cart()
        other["id"] = otherID.uuidString
        let active = try json([["id": id.uuidString, "cart_id": cartID.uuidString]])
        let details = try purchaseResponse(id: id, itemStatus: .bought)
        let client = ShoppingRequestStub(responses: try [
            json([["id": otherID.uuidString]]), json(other), json([]),
            active, details, json(cart()), active, details
        ])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        list.setAccount(account)
        await list.refresh()
        XCTAssertEqual(list.cart?.id, otherID)
        XCTAssertTrue(list.hasCacheFailure)
        await cache.setFailing(false)
        await client.setOffline(true)
        await list.refresh()
        XCTAssertEqual(list.cart?.id, otherID)
        let untouched = try await cache.load(account: account)
        XCTAssertEqual(untouched?.trip?.plan.id, id)
        await client.setOffline(false)
        await list.refresh()
        XCTAssertNil(list.failure)
        XCTAssertFalse(list.hasCacheFailure)
        XCTAssertEqual(list.trip?.page, snapshot.trip?.page)
        XCTAssertEqual(list.trip?.boughtCount, 1)
        XCTAssertEqual(list.cart?.id, cartID)
    }

    func testCompletedTripWithDeletedCartUnlocksListAndReportsFailedKeep() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileShoppingListCache(directory: folder)
        let id = UUID()
        let account = ShoppingListPreview.account
        let snapshot = try await savedTrip(id: id, finishing: .keep)
        try await cache.save(snapshot, account: account)
        let state: [String: Any] = ["id": id.uuidString, "cart_id": NSNull(), "status": "completed"]
        let otherID = UUID()
        var other = cart()
        other["id"] = otherID.uuidString
        let client = ShoppingRequestStub(responses: try [json(state), json([["id": otherID.uuidString]]), json(other), json([])])
        let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
        list.setAccount(account)
        await list.refresh()
        XCTAssertNil(list.trip)
        XCTAssertFalse(list.selection.isShopping)
        XCTAssertTrue(list.showsDeletedCartNotice)
        XCTAssertEqual(list.cart?.id, otherID)
        let persisted = try await cache.load(account: account)
        XCTAssertNil(persisted?.trip)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "GET", "GET", "GET"])
        XCTAssertEqual(requests.first?.path, "plans/\(id.uuidString)")
    }

    func testCartDisappearingDuringKeepIsTerminalOnlyForNotFound() async throws {
        let id = UUID()
        let state = try json(["id": id.uuidString, "cart_id": cartID.uuidString, "status": "completed"])
        for status in [404, 503] {
            let client = ShoppingRequestStub(responses: [state])
            await client.rejectNextPatch(.http(status: status, code: nil, requestID: nil, retryAfter: nil))
            do {
                let result = try await APIShoppingListService(client: client).finishPlan(id: id, cartID: cartID, list: .keep, resuming: true)
                XCTAssertEqual(status, 404)
                XCTAssertNil(result)
            } catch {
                XCTAssertEqual(status, 503)
                XCTAssertEqual((error as? APIError)?.status, status)
            }
        }
    }

    func testGuestChangesWaitForTheTripDispositionAcrossRelaunch() async throws {
        for choice in [ShoppingTrip.ListDisposition.keep, .delete] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let cache = FileShoppingListCache(directory: folder)
            let id = UUID()
            let account = ShoppingListPreview.account
            let initial = ShoppingRequestStub(responses: try restoreResponses(planID: id))
            let first = ShoppingListRepository(service: APIShoppingListService(client: initial), cache: cache)
            first.selection.setQuantity(1, for: "1")
            first.setAccount(account)
            await first.refresh()
            let initialRequests = await initial.requests
            XCTAssertTrue(initialRequests.allSatisfy { $0.method == "GET" })
            XCTAssertEqual(first.selection.quantity(for: "1"), 2)
            let saved = try await cache.load(account: account)
            XCTAssertEqual(saved?.pending[.cart(cartID)], ["1": 1])

            var changed = cart()
            changed["items"] = [["product": product(), "quantity": 1]]
            let current = try json(cart())
            let responses = try [current, json([["id": id.uuidString, "cart_id": cartID.uuidString]]),
                                 purchaseResponse(id: id, itemStatus: .planned), purchaseResponse(id: id, itemStatus: .planned, completed: true)]
            let afterFinish = choice == .keep ? try [current, current, json([]), json(changed)] : try [Data(), json([])]
            let client = ShoppingRequestStub(responses: responses + afterFinish)
            let list = ShoppingListRepository(service: APIShoppingListService(client: client), cache: cache)
            list.setAccount(account)
            await list.refresh()
            XCTAssertNil(list.failure)
            XCTAssertEqual(list.trip?.items.first?.quantity, 2)
            XCTAssertEqual(list.selection.quantity(for: "1"), 2)
            let finished = await list.finishShopping(choice)
            XCTAssertTrue(finished)
            XCTAssertNil(list.failure)
            XCTAssertEqual(list.selection.quantity(for: "1"), choice == .keep ? 1 : 0)
            let writes = await client.requests.filter { $0.method != "GET" }
            let completion = "plans/\(id.uuidString)/complete"
            let cartPath = "carts/\(cartID.uuidString)"
            XCTAssertEqual(writes.map(\.path), choice == .keep ? [completion, cartPath, cartPath + "/items/1"] : [completion, cartPath])
            XCTAssertEqual(writes.map(\.method), choice == .keep ? ["POST", "PATCH", "PATCH"] : ["POST", "DELETE"])
        }
    }
}
