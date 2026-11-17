import XCTest
@testable import vezzi_ios

@MainActor
final class ShoppingRouteViewModelTests: XCTestCase {
    func testRouteKeepsAddressBoundToItsSnapshotUntilOriginChanges() throws {
        let list = ShoppingListRepository()
        list.setRoute(origin: list.origin, options: .init(), address: "Original street")
        let plan = ShoppingPlan(id: UUID(), total: 100, savings: nil, totalSeconds: 600, walkingMeters: 500,
                                stops: [], points: [list.origin], usesRoadNetwork: true, isSynthetic: true)
        let snapshot = try XCTUnwrap(ShoppingRoutesSnapshot(plans: [plan], selectedID: plan.id,
                                                            origin: list.origin, isSaved: false, originAddress: list.originAddress))
        let model = ShoppingRouteViewModel(snapshot: snapshot, list: list, location: RouteLocationStub())
        let point = ShoppingCoordinate(latitude: 60.015, longitude: 30.26)
        list.setRoute(origin: point, options: .init(), address: "New street")
        XCTAssertEqual(model.originAddress, "Original street")
        XCTAssertEqual(model.origin, snapshot.origin)
        model.changeRoute(point, options: .init(), address: "New street")
        XCTAssertEqual(model.origin, point)
        XCTAssertEqual(model.originAddress, "New street")
    }

    func testLocationDoesNotChangeRouteOriginOrSelection() async throws {
        let service = RouteLocationStub()
        let list = ShoppingListPreview.repository()
        let model = model(list: list, location: service)
        let originalOrigin = model.origin
        let originalPlan = model.selectedID
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        XCTAssertTrue(model.isLocating)
        let coordinate = ShoppingCoordinate(latitude: 60.015, longitude: 30.26)
        service.complete(.success(coordinate))
        let result = await request.value
        XCTAssertEqual(result, coordinate)
        XCTAssertEqual(model.deviceCoordinate, coordinate)
        XCTAssertEqual(model.origin, originalOrigin)
        XCTAssertEqual(list.origin, originalOrigin)
        XCTAssertEqual(model.selectedID, originalPlan)
        XCTAssertFalse(model.isRecalculating)
        XCTAssertFalse(model.isLocating)
    }

    func testCancelledFixCannotMoveCameraOrPublishError() async {
        let service = RouteLocationStub()
        let model = model(list: ShoppingListPreview.repository(), location: service)
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        request.cancel()
        service.complete(.success(.previewOrigin))
        let result = await request.value
        XCTAssertNil(result)
        XCTAssertNil(model.deviceCoordinate)
        XCTAssertNil(model.locationError)
        XCTAssertFalse(model.isLocating)
    }

    func testFailureRetainsLastFixAndCanBeDismissed() async {
        let service = RouteLocationStub()
        let model = model(list: ShoppingListPreview.repository(), location: service)
        let first = Task { await model.locate() }
        await service.waitUntilRequested()
        service.complete(.success(.previewOrigin))
        _ = await first.value
        let second = Task { await model.locate() }
        await service.waitUntilRequested()
        let duplicate = await model.locate()
        XCTAssertNil(duplicate)
        XCTAssertEqual(service.requestCount, 2)
        service.complete(.failure(DeviceLocationError.denied))
        let result = await second.value
        XCTAssertNil(result)
        XCTAssertEqual(model.deviceCoordinate, .previewOrigin)
        XCTAssertEqual(model.locationError, .denied)
        XCTAssertFalse(model.isLocating)
        model.clearLocationError()
        XCTAssertNil(model.locationError)
    }

    private func model(list: ShoppingListRepository, location: any DeviceLocating) -> ShoppingRouteViewModel {
        let plan = ShoppingPlan(id: UUID(), total: 100, savings: nil, totalSeconds: 600, walkingMeters: 500,
                                stops: [], points: [.previewOrigin], usesRoadNetwork: true, isSynthetic: true)
        let snapshot = ShoppingRoutesSnapshot(plans: [plan], selectedID: plan.id, origin: list.origin, isSaved: false)!
        return ShoppingRouteViewModel(snapshot: snapshot, list: list, location: location)
    }
}

@MainActor
final class RouteLocationStub: DeviceLocating {
    private var continuation: CheckedContinuation<ShoppingCoordinate, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    // Avoid the isolated-deinit runtime crash on early iOS 26.
    nonisolated deinit {}

    func currentCoordinate() async throws -> ShoppingCoordinate {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilRequested() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func complete(_ result: Result<ShoppingCoordinate, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}
