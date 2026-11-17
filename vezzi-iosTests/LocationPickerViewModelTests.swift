import XCTest
@testable import vezzi_ios

@MainActor
final class LocationPickerViewModelTests: XCTestCase {
    func testSelectionAreaCoversAllCurrentStoresWithMargin() {
        // Store coordinates from the 2026-11-17 API response, independent of the chosen center.
        let area = LocationSelectionArea.supported
        let stores = [
            ShoppingCoordinate(latitude: 60.0081, longitude: 30.2454),
            ShoppingCoordinate(latitude: 60.0097, longitude: 30.2487),
            ShoppingCoordinate(latitude: 60.0096, longitude: 30.2485),
            ShoppingCoordinate(latitude: 60.0104, longitude: 30.2501),
            ShoppingCoordinate(latitude: 60.0118, longitude: 30.2528),
            ShoppingCoordinate(latitude: 60.012, longitude: 30.253),
            ShoppingCoordinate(latitude: 60.0134, longitude: 30.2555),
            ShoppingCoordinate(latitude: 60.0139, longitude: 30.2562),
            ShoppingCoordinate(latitude: 60.0141, longitude: 30.2565),
            ShoppingCoordinate(latitude: 60.0142, longitude: 30.2564),
            ShoppingCoordinate(latitude: 60.0146, longitude: 30.2572),
            ShoppingCoordinate(latitude: 60.0176, longitude: 30.2618),
            ShoppingCoordinate(latitude: 60.0191, longitude: 30.2644),
            ShoppingCoordinate(latitude: 60.0196, longitude: 30.2652),
            ShoppingCoordinate(latitude: 60.02, longitude: 30.2658),
            ShoppingCoordinate(latitude: 60.02, longitude: 30.2659),
            ShoppingCoordinate(latitude: 60.0203, longitude: 30.2663),
            ShoppingCoordinate(latitude: 60.0203, longitude: 30.2662),
            ShoppingCoordinate(latitude: 60.0208, longitude: 30.267),
            ShoppingCoordinate(latitude: 60.021, longitude: 30.2673)
        ]
        XCTAssertEqual(area.radiusMeters, 1_000)
        let innerArea = LocationSelectionArea(center: area.center, radiusMeters: area.radiusMeters - 50)
        XCTAssertTrue(stores.allSatisfy(innerArea.contains))
        XCTAssertTrue(area.contains(.previewOrigin), "The existing starting point remains usable")
    }

    func testOutsideAddressAndLocationCannotBeConfirmed() async {
        let service = LocationStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: service)
        XCTAssertTrue(model.canConfirm)
        let outside = ShoppingCoordinate(latitude: 59.9, longitude: 30.3)
        model.choose(AddressSearchSelection(coordinate: outside, address: "Outside address"))
        XCTAssertFalse(model.canConfirm)
        XCTAssertTrue(model.isOutsideSelectionArea)
        model.returnToSelectionArea()
        XCTAssertTrue(model.canConfirm)
        XCTAssertNil(model.address)
        let request = Task { await model.locate() }
        await service.waitUntilRequested()
        XCTAssertFalse(model.canConfirm)
        service.complete(outside)
        await request.value
        XCTAssertFalse(model.canConfirm)
        XCTAssertTrue(model.isOutsideSelectionArea)
    }

    func testBoundaryCrossingsDuringPanPreservePointAndReturnPreservesOptions() {
        let options = ShoppingRouteOptions(returnToStart: true, radiusMeters: 750)
        let model = LocationPickerViewModel(coordinate: .previewOrigin, options: options, service: LocationStub())
        model.beginMoving()
        model.updateSelectionAvailability(false)
        XCTAssertTrue(model.isOutsideSelectionArea)
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.coordinate, .previewOrigin)
        model.updateSelectionAvailability(true)
        XCTAssertFalse(model.isOutsideSelectionArea)
        XCTAssertFalse(model.canConfirm)
        model.choose(ShoppingCoordinate(latitude: 59.9, longitude: 30.3))
        XCTAssertFalse(model.canConfirm)
        model.returnToSelectionArea()
        model.updateSelectionAvailability(false)
        XCTAssertEqual(model.coordinate, model.selectionArea.center)
        XCTAssertEqual(model.options, options)
        XCTAssertTrue(model.canConfirm)
    }

    func testSelectionBoundaryIncludesCenterAndRejectsOutsidePoints() {
        let area = LocationSelectionArea.supported
        XCTAssertTrue(area.contains(area.center))
        XCTAssertTrue(area.contains(ShoppingCoordinate(latitude: 60.017, longitude: 30.2586)))
        XCTAssertFalse(area.contains(ShoppingCoordinate(latitude: 60.024, longitude: 30.2586)))
        XCTAssertFalse(area.contains(ShoppingCoordinate(latitude: .nan, longitude: 30)))
        XCTAssertTrue(area.boundary(vertexCount: 128).allSatisfy(area.contains))
        let outside = LocationSelectionArea(center: area.center, radiusMeters: 1_050)
        XCTAssertTrue(outside.boundary(vertexCount: 16).allSatisfy { !area.contains($0) })
    }

    func testRestoredUnsupportedRadiusIsNormalizedOnlyInThePickerDraft() {
        for radius in [1_000, 5_000] {
            let oldOptions = ShoppingRouteOptions(returnToStart: true, radiusMeters: radius)
            let model = LocationPickerViewModel(coordinate: .previewOrigin, options: oldOptions, service: LocationStub())
            XCTAssertEqual(model.options, ShoppingRouteOptions(returnToStart: true, radiusMeters: 750))
            XCTAssertEqual(oldOptions.radiusMeters, radius)
        }
        let unlimited = LocationPickerViewModel(coordinate: .previewOrigin, service: LocationStub())
        XCTAssertNil(unlimited.options.radiusMeters)
    }

    func testChosenAddressWinsOverPendingLocationAndReverseLookup() async {
        let location = LocationStub()
        let resolver = AddressStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: location, addressResolver: resolver)
        let fix = Task { await model.locate() }
        let lookup = Task { await model.resolveAddress() }
        await location.waitUntilRequested()
        await resolver.waitForRequest(.previewOrigin)
        let selected = AddressSearchSelection(coordinate: ShoppingCoordinate(latitude: 60.01, longitude: 30.3),
                                              address: "Chosen street, 7")
        model.choose(selected)
        location.complete(.previewOrigin)
        resolver.complete(.previewOrigin, result: .success("Old address"))
        await fix.value
        await lookup.value
        await model.resolveAddress()
        XCTAssertEqual(model.coordinate, selected.coordinate)
        XCTAssertEqual(model.address, selected.address)
        XCTAssertFalse(model.isLocating)
        XCTAssertFalse(model.isResolvingAddress)
    }

    func testAddressOmitsResolvedCityWithoutChangingStreetNames() {
        XCTAssertEqual(MapKitAddressResolver.streetAddress("Комендантский проспект, 12 литА, Санкт-Петербург", city: "Санкт-Петербург"),
                       "Комендантский проспект, 12 литА")
        XCTAssertEqual(MapKitAddressResolver.streetAddress("г. Санкт-Петербург, Санкт-Петербургское шоссе, 10", city: "Санкт-Петербург"),
                       "Санкт-Петербургское шоссе, 10")
        XCTAssertEqual(MapKitAddressResolver.streetAddress("  Cupertino\n1 Apple Park Way  ", city: "cupertino"), "1 Apple Park Way")
        XCTAssertEqual(MapKitAddressResolver.streetAddress("Unknown street, 7", city: nil), "Unknown street, 7")
        XCTAssertNil(MapKitAddressResolver.streetAddress("Санкт-Петербург", city: "Санкт-Петербург"))
    }

    func testAddressLookupRejectsOlderPointAndKeepsNewRequestLoading() async {
        let resolver = AddressStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: LocationStub(), addressResolver: resolver)
        let first = Task { await model.resolveAddress() }
        await resolver.waitForRequest(.previewOrigin)
        let next = ShoppingCoordinate(latitude: 60.01, longitude: 30.3)
        model.choose(next)
        let second = Task { await model.resolveAddress() }
        await resolver.waitForRequest(next)
        resolver.complete(.previewOrigin, result: .success("Old street"))
        await first.value
        XCTAssertNil(model.address)
        XCTAssertTrue(model.isResolvingAddress)
        resolver.complete(next, result: .success("New street, 12"))
        await second.value
        XCTAssertEqual(model.address, "New street, 12")
        XCTAssertFalse(model.isResolvingAddress)
    }

    func testMovingRejectsLateAddressEvenBeforeCoordinatesChange() async {
        let resolver = AddressStub()
        let model = LocationPickerViewModel(coordinate: .previewOrigin, service: LocationStub(), addressResolver: resolver)
        let request = Task { await model.resolveAddress() }
        await resolver.waitForRequest(.previewOrigin)
        model.beginMoving()
        resolver.complete(.previewOrigin, result: .success("Old street"))
        await request.value
        XCTAssertNil(model.address)
        XCTAssertFalse(model.isResolvingAddress)
        XCTAssertTrue(model.isMoving)
    }

    func testCancelledAddressLookupAndFailureDoNotBlockPointConfirmation() async {
        let resolver = AddressStub()
        let options = ShoppingRouteOptions(returnToStart: true, radiusMeters: 500)
        let model = LocationPickerViewModel(coordinate: .previewOrigin, options: options,
                                            service: LocationStub(), addressResolver: resolver)
        let cancelled = Task { await model.resolveAddress() }
        await resolver.waitForRequest(.previewOrigin)
        cancelled.cancel()
        resolver.complete(.previewOrigin, result: .success("Cancelled address"))
        await cancelled.value
        XCTAssertNil(model.address)
        XCTAssertFalse(model.isResolvingAddress)
        let retry = Task { await model.resolveAddress() }
        await resolver.waitForRequest(.previewOrigin)
        resolver.complete(.previewOrigin, result: .failure(URLError(.notConnectedToInternet)))
        await retry.value
        XCTAssertNil(model.address)
        XCTAssertFalse(model.isResolvingAddress)
        XCTAssertEqual(model.coordinate, .previewOrigin)
        XCTAssertEqual(model.options, options)
        XCTAssertNil(model.error)
    }

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

    // Avoid the isolated-deinit runtime crash on early iOS 26, also handled in app-owned models.
    nonisolated deinit {}

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

@MainActor
private final class AddressStub: AddressResolving {
    private var requests: [(ShoppingCoordinate, CheckedContinuation<String?, Error>)] = []
    private var waiter: (ShoppingCoordinate, CheckedContinuation<Void, Never>)?

    func address(for coordinate: ShoppingCoordinate) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            requests.append((coordinate, continuation))
            if waiter?.0 == coordinate { waiter?.1.resume(); waiter = nil }
        }
    }

    func waitForRequest(_ coordinate: ShoppingCoordinate) async {
        if requests.contains(where: { $0.0 == coordinate }) { return }
        await withCheckedContinuation { waiter = (coordinate, $0) }
    }

    func complete(_ coordinate: ShoppingCoordinate, result: Result<String?, Error>) {
        guard let index = requests.firstIndex(where: { $0.0 == coordinate }) else { return }
        requests.remove(at: index).1.resume(with: result)
    }
}
