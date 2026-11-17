import MapLibre
import UIKit
import XCTest
@testable import vezzi_ios

@MainActor
final class RouteMapViewTests: XCTestCase {
    func testTapZoomCommitsVisiblePointWithoutAnActiveRecognizer() async throws {
        for reason: MLNCameraChangeReason in [.gestureZoomIn, .gestureZoomOut] {
            try await withMap { container in
                let map = container.map
                let model = LocationPickerViewModel(coordinate: .defaultOrigin, service: UnusedLocation())
                let committed = expectation(description: "Tap zoom commits the point")
                committed.assertForOverFulfill = true
                let coordinator = RouteMapView.Coordinator(RouteMapView(
                    origin: model.coordinate, bottomInset: 220,
                    onInteractionBegan: model.beginMoving,
                    onSelectCoordinate: { point in model.choose(point); committed.fulfill() }
                ))
                coordinator.mapView = map
                let selection = MapPointSelection()
                selection.install(in: container)
                coordinator.pointSelection = selection
                map.setCenter(CLLocationCoordinate2D(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude),
                              zoomLevel: 15, animated: false)
                coordinator.update(map)

                // Discrete recognizers are no longer .began/.changed during these callbacks.
                coordinator.mapView(map, regionWillChangeWith: reason, animated: true)
                XCTAssertTrue(model.isMoving)
                XCTAssertFalse(model.canConfirm)
                let latitude = reason == .gestureZoomIn ? 60.015 : 60.04
                map.setCenter(CLLocationCoordinate2D(latitude: latitude, longitude: 30.257),
                              zoomLevel: reason == .gestureZoomIn ? 16 : 14, animated: false)
                selection.render(map)
                let expectedPoint = selection.visibleCoordinate(in: map)
                XCTAssertNotEqual(expectedPoint, model.coordinate)
                coordinator.mapView(map, regionDidChangeWith: reason, animated: true)

                await fulfillment(of: [committed], timeout: 2)
                XCTAssertFalse(model.isMoving)
                XCTAssertEqual(model.coordinate.latitude, expectedPoint.latitude, accuracy: 0.000001)
                XCTAssertEqual(model.coordinate.longitude, expectedPoint.longitude, accuracy: 0.000001)
                XCTAssertEqual(model.canConfirm, model.selectionArea.contains(expectedPoint))
            }
        }
    }

    func testProgrammaticCameraChangeDoesNotStartOrCommitSelection() async throws {
        try await withMap { container in
            let unexpected = expectation(description: "Programmatic camera movement does not select a point")
            unexpected.isInverted = true
            let coordinator = RouteMapView.Coordinator(RouteMapView(
                origin: .defaultOrigin,
                onInteractionBegan: { unexpected.fulfill() },
                onSelectCoordinate: { _ in unexpected.fulfill() }
            ))
            coordinator.mapView = container.map
            let selection = MapPointSelection()
            selection.install(in: container)
            coordinator.pointSelection = selection
            coordinator.update(container.map)
            coordinator.mapView(container.map, regionWillChangeWith: .programmatic, animated: true)
            coordinator.mapView(container.map, regionDidChangeWith: .programmatic, animated: true)
            await fulfillment(of: [unexpected], timeout: 0.2)
        }
    }

    func testZoomDuringPanCommitsThePointBeforeZooming() async throws {
        try await checkZoom(.zoomIn, afterGestureEnds: false)
    }

    func testZoomBetweenGestureEndAndDeferredCommitPreservesConfirmation() async throws {
        try await checkZoom(.zoomOut, afterGestureEnds: true)
    }

    func testNewGestureDiscardsAnOlderUnappliedZoomRequest() async throws {
        try await checkZoom(.zoomIn, afterGestureEnds: false, requestedBeforeGesture: true)
    }

    func testRouteGestureCancelsFitsIncludingLateCollapseAndInitiallyCoveredMap() async throws {
        for (initialHeight, collapseAfterGesture) in [(560.0, false), (560.0, true), (1_000.0, true)] {
            try await withMap { container in
                let map = container.map
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in map.style != nil }, object: nil)
                await fulfillment(of: [ready], timeout: 3)
                let coordinator = RouteMapView.Coordinator(RouteMapView(origin: .defaultOrigin,
                    plan: plan(), bottomInset: initialHeight))
                coordinator.mapView = map
                coordinator.mapView(map, didFinishLoading: try XCTUnwrap(map.style))

                let gesture = TestPan()
                map.addGestureRecognizer(gesture)
                gesture.begin()
                coordinator.mapView(map, regionWillChangeWith: .gesturePan, animated: false)
                map.setCenter(CLLocationCoordinate2D(latitude: 60.016, longitude: 30.26), zoomLevel: 17, animated: false)
                let center = map.centerCoordinate
                if !collapseAfterGesture {
                    coordinator.parent.bottomInset = 220
                    coordinator.update(map)
                }
                gesture.end()
                coordinator.mapView(map, regionDidChangeWith: .gesturePan, animated: false)
                if collapseAfterGesture {
                    coordinator.parent.bottomInset = 220
                    coordinator.update(map)
                }
                // Also flush the old implementation's deferred fit and a subsequent style/layout update.
                await Task.yield()
                coordinator.update(map, styleReloaded: true)
                assertCamera(map, center: center, zoom: 17)

                coordinator.parent.plan = plan()
                coordinator.update(map)
                assertCamera(map, center: center, zoom: 17)
                coordinator.parent.cameraRequest = MapCameraRequest(action: .fitRoute)
                coordinator.update(map)
                XCTAssertNotEqual(map.zoomLevel, 17, "Explicitly selecting another route still fits it")
            }
        }
    }

    func testPickerCollapseKeepsUserCameraAndCommitsFinalPinBeforeNewRadiusOrAddress() async throws {
        for radius: Int? in [nil, 500] {
            try await withMap { container in
                let map = container.map
                let model = LocationPickerViewModel(coordinate: .defaultOrigin, service: UnusedLocation())
                let coordinator = RouteMapView.Coordinator(RouteMapView(origin: model.coordinate))
                coordinator.mapView = map
                let selection = MapPointSelection()
                selection.install(in: container)
                coordinator.pointSelection = selection
                var expectedCommit: XCTestExpectation?
                @MainActor func update(bottom: CGFloat, live: CGFloat? = nil, radius: Int?) {
                    coordinator.parent = RouteMapView(origin: model.coordinate, bottomInset: bottom,
                        selectionRadius: radius, selectionLiveBottomInset: live,
                        onInteractionBegan: model.beginMoving, onSelectCoordinate: { coordinate in
                            model.choose(coordinate)
                            expectedCommit?.fulfill()
                            expectedCommit = nil
                        })
                    coordinator.update(map)
                }
                map.setCenter(CLLocationCoordinate2D(latitude: 60.01455, longitude: 30.258), zoomLevel: 15, animated: false)
                update(bottom: 560, radius: radius)
                let gesture = TestPan()
                map.addGestureRecognizer(gesture)
                gesture.begin()
                coordinator.mapView(map, regionWillChangeWith: .gesturePan, animated: false)
                map.setCenter(CLLocationCoordinate2D(latitude: 60.015, longitude: 30.259), zoomLevel: 17, animated: false)
                let center = map.centerCoordinate
                update(bottom: 560, live: 340, radius: radius)
                let ended = expectation(description: "Gesture commits the point")
                expectedCommit = ended
                gesture.end()
                coordinator.mapView(map, regionDidChangeWith: .gesturePan, animated: false)
                await fulfillment(of: [ended], timeout: 2)
                assertCamera(map, center: center, zoom: 17)
                XCTAssertTrue(model.canConfirm)

                let collapsed = expectation(description: "Late panel settlement commits its final pin")
                expectedCommit = collapsed
                update(bottom: 220, radius: radius)
                await fulfillment(of: [collapsed], timeout: 2)
                await assertSettledPin(selection, in: map, at: model.coordinate)
                update(bottom: 220, radius: radius)
                assertCamera(map, center: center, zoom: 17)

                update(bottom: 220, radius: 750)
                XCTAssertNotEqual(map.zoomLevel, 17, "A newly chosen radius still fits its circle")
                let addressPoint = ShoppingCoordinate(latitude: 60.016, longitude: 30.258)
                model.choose(addressPoint)
                update(bottom: 220, radius: 750)
                await assertSettledPin(selection, in: map, at: addressPoint)
            }
        }
    }

    private func assertSettledPin(_ selection: MapPointSelection, in map: MLNMapView, at point: ShoppingCoordinate) async {
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let pin = selection.visibleCoordinate(in: map)
            return abs(pin.latitude - point.latitude) < 0.000001 && abs(pin.longitude - point.longitude) < 0.000001
        }, object: nil)
        await fulfillment(of: [settled], timeout: 2)
    }

    private func assertCamera(_ map: MLNMapView, center: CLLocationCoordinate2D, zoom: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(map.zoomLevel, zoom, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(map.centerCoordinate.latitude, center.latitude, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(map.centerCoordinate.longitude, center.longitude, accuracy: 0.000001, file: file, line: line)
    }

    private func plan() -> ShoppingPlan {
        ShoppingPlan(id: UUID(), total: 100, savings: nil, totalSeconds: 300, walkingMeters: 500, stops: [],
                     points: [.defaultOrigin, ShoppingCoordinate(latitude: 60.02, longitude: 30.26)],
                     usesRoadNetwork: true, isSynthetic: false)
    }

    private func checkZoom(_ action: MapCameraRequest.Action, afterGestureEnds: Bool,
                           requestedBeforeGesture: Bool = false) async throws {
        try await withMap { container in
            let model = LocationPickerViewModel(coordinate: .defaultOrigin, service: UnusedLocation())
            let committed = expectation(description: "Gesture selection is committed once")
            committed.assertForOverFulfill = true
            let coordinator = RouteMapView.Coordinator(RouteMapView(
                origin: model.coordinate, onInteractionBegan: model.beginMoving,
                onSelectCoordinate: { point in model.choose(point); committed.fulfill() }
            ))
            let map = container.map
            coordinator.mapView = map
            let selection = MapPointSelection()
            selection.install(in: container)
            coordinator.pointSelection = selection
            map.setCenter(CLLocationCoordinate2D(latitude: model.coordinate.latitude, longitude: model.coordinate.longitude),
                          zoomLevel: 15, animated: false)
            coordinator.update(map)

            if requestedBeforeGesture { coordinator.parent.cameraRequest = MapCameraRequest(action: action) }

            let gesture = TestPan()
            map.addGestureRecognizer(gesture)
            gesture.begin()
            coordinator.mapView(map, regionWillChangeWith: .gesturePan, animated: false)
            XCTAssertFalse(model.canConfirm)
            map.setCenter(CLLocationCoordinate2D(latitude: 60.015, longitude: 30.257), animated: false)
            selection.render(map)
            let expectedPoint = selection.visibleCoordinate(in: map)
            let previousZoom = map.zoomLevel
            XCTAssertTrue(LocationSelectionArea.supported.contains(expectedPoint))

            if afterGestureEnds {
                gesture.end()
                coordinator.mapView(map, regionDidChangeWith: .gesturePan, animated: false)
            }
            if !requestedBeforeGesture { coordinator.parent.cameraRequest = MapCameraRequest(action: action) }
            coordinator.update(map)
            XCTAssertEqual(map.zoomLevel, previousZoom, accuracy: 0.001, "Zoom must wait for the pending selection")
            if !afterGestureEnds {
                gesture.end()
                coordinator.mapView(map, regionDidChangeWith: .gesturePan, animated: false)
            }

            await fulfillment(of: [committed], timeout: 2)
            XCTAssertTrue(model.canConfirm)
            XCTAssertEqual(model.coordinate.latitude, expectedPoint.latitude, accuracy: 0.000001)
            XCTAssertEqual(model.coordinate.longitude, expectedPoint.longitude, accuracy: 0.000001)
            let expectedZoom = previousZoom + (requestedBeforeGesture ? 0 : (action == .zoomIn ? 1 : -1))
            let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(map.zoomLevel - expectedZoom) < 0.001 }, object: nil)
            await fulfillment(of: [zoomed], timeout: 2)
        }
    }

    private func withMap(_ body: @MainActor (RouteMapView.MapContainerView) async throws -> Void) async throws {
        // Exercise the real map/coordinator with a local empty style, without network or location access.
        let styleURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(#"{"version":8,"sources":{},"layers":[]}"#.utf8).write(to: styleURL)
        defer { try? FileManager.default.removeItem(at: styleURL) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let container = RouteMapView.MapContainerView(styleURL: styleURL)
        container.map.automaticallyAdjustsContentInset = false
        let controller = UIViewController()
        controller.view = container
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        container.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil }

        try await body(container)
    }

}

@MainActor private final class TestPan: UIPanGestureRecognizer {
    func begin() { state = .began }
    func end() { state = .ended }
}

@MainActor private final class UnusedLocation: DeviceLocating {
    nonisolated deinit {}
    func currentCoordinate() async throws -> ShoppingCoordinate {
        XCTFail("Map gestures must not request device location")
        throw DeviceLocationError.unavailable
    }
}
