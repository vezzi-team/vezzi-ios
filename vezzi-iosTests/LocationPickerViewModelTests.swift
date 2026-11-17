import XCTest
@testable import vezzi_ios

@MainActor
final class LocationPickerViewModelTests: XCTestCase {
    func testDeniedLocationKeepsManualPointUsable() async {
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: LocationStub(error: .denied))
        await model.locate()
        XCTAssertEqual(model.coordinate, .previewOrigin)
        XCTAssertFalse(model.isLocating)
        XCTAssertNotNil(model.error)
        let manual = ShoppingCoordinate(latitude: 59.9, longitude: 30.3)
        model.choose(manual)
        XCTAssertEqual(model.coordinate, manual)
        XCTAssertNil(model.error)
    }

    func testCancelledLocationCannotOverwriteManualSelection() async {
        let service = LocationStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: service)
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        request.cancel()
        let manual = ShoppingCoordinate(latitude: 59.9, longitude: 30.3)
        model.choose(manual)
        service.complete(.previewOrigin)
        await request.value
        XCTAssertEqual(model.coordinate, manual)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLocating)
    }

    func testCancelledLocationIgnoresLateFailureAndAllowsRetry() async {
        let service = LocationStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: service)
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        request.cancel()
        service.fail(.unavailable)
        await request.value
        XCTAssertEqual(model.coordinate, .previewOrigin)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLocating)

        let retry = Task { await model.locate() }
        await service.waitUntilRequested()
        let located = ShoppingCoordinate(latitude: 59.9, longitude: 30.3)
        service.complete(located)
        await retry.value
        XCTAssertEqual(model.coordinate, located)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLocating)
    }

    func testLocationIsAppliedOnlyAfterSuccess() async {
        let service = LocationStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: service)
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        XCTAssertTrue(model.isLocating)
        XCTAssertEqual(model.coordinate, .previewOrigin)
        let located = ShoppingCoordinate(latitude: 59.9, longitude: 30.3)
        service.complete(located)
        await request.value
        XCTAssertEqual(model.coordinate, located)
        XCTAssertFalse(model.isLocating)
    }
}

@MainActor
private final class LocationStub: DeviceLocating {
    let error: DeviceLocationError?
    private var continuation: CheckedContinuation<ShoppingCoordinate, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    init(error: DeviceLocationError? = nil) { self.error = error }

    func currentCoordinate() async throws -> ShoppingCoordinate {
        if let error { throw error }
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
    func complete(_ coordinate: ShoppingCoordinate) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    func fail(_ error: DeviceLocationError) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
