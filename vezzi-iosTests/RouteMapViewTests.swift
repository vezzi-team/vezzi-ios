import MapKit
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

    func testRendererReleasesWhenUIKitTearsDownTheMap() async throws {
        try await withMap { container in
            let map = container.map
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in map.style != nil }, object: nil)
            await fulfillment(of: [ready], timeout: 5)
            let style = try XCTUnwrap(map.style)
            let points = plan().points
            let released = expectation(description: "Renderer released on the UIKit main queue")

            // UIKit can release the map between Swift tasks on the main run loop.
            DispatchQueue.main.async {
                weak var reference: RouteLineRenderer?
                autoreleasepool {
                    let renderer = RouteLineRenderer(style: style, traits: map.traitCollection)
                    reference = renderer
                    renderer.setRoute(points, repeatedSections: [])
                    renderer.reveal(to: 0.5)
                }
                XCTAssertNil(reference)
                released.fulfill()
            }
            await fulfillment(of: [released], timeout: 5)
        }
    }

    func testRepeatedRoadChangesColorOnSecondPassAndResetsForAnotherPlan() async throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            try await withMap { container in
                container.overrideUserInterfaceStyle = appearance
                let map = container.map
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in map.style != nil }, object: nil)
                await fulfillment(of: [ready], timeout: 5)
                let style = try XCTUnwrap(map.style)
                let background = MLNBackgroundStyleLayer(identifier: "paper")
                background.backgroundColor = NSExpression(forConstantValue: appearance == .light ? UIColor.white : UIColor.darkGray)
                style.addLayer(background)

                let center = ShoppingCoordinate.defaultOrigin.clCoordinate
                map.setCenter(center, zoomLevel: 17, animated: false)
                let midpoint = map.convert(center, toPointTo: map)
                @MainActor func point(_ x: CGFloat, _ y: CGFloat = 0) -> ShoppingCoordinate {
                    let coordinate = map.convert(CGPoint(x: midpoint.x + x, y: midpoint.y + y), toCoordinateFrom: map)
                    return ShoppingCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
                }
                let a = point(-90), b = point(0), c = point(90), d = point(90, -60)
                let once = point(-45), early = point(25), late = point(75), bend = point(90, -20)
                let beside = point(40, -15)
                let points = [a, b, c, d, c, b, point(0, 60)]
                func plan(road: Bool) -> ShoppingPlan {
                    ShoppingPlan(id: UUID(), total: 100, savings: nil, totalSeconds: 500, walkingMeters: 600,
                                 stops: [], points: points, usesRoadNetwork: road, isSynthetic: false)
                }
                let coordinator = RouteMapView.Coordinator(RouteMapView(origin: a, plan: plan(road: true)))
                coordinator.mapView = map
                coordinator.mapView(map, didFinishLoading: style)
                coordinator.cancelReveal()
                map.setCenter(center, zoomLevel: 17, animated: false)
                @MainActor func snapshot() -> UIImage {
                    UIGraphicsImageRenderer(bounds: map.bounds).image { _ in
                        container.drawHierarchy(in: map.bounds, afterScreenUpdates: true)
                    }
                }
                @MainActor func strength(_ image: UIImage, at coordinate: ShoppingCoordinate) throws -> Double {
                    try orangeStrength(in: image, at: map.convert(coordinate.clCoordinate, toPointTo: map))
                }
                @MainActor func frame(with point: ShoppingCoordinate, in range: ClosedRange<Double>) async -> UIImage {
                    let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        guard let value = try? strength(snapshot(), at: point) else { return false }
                        return range.contains(value)
                    }, object: nil)
                    await fulfillment(of: [painted], timeout: 5)
                    return snapshot()
                }

                let orange = 0.45...1.0, violet = -1.0 ... -0.15
                @MainActor func assertFrames(keeping point: ShoppingCoordinate, in range: ClosedRange<Double>,
                                             after progress: Double) async throws {
                    coordinator.applyReveal(progress: progress, animated: true)
                    for _ in 0..<6 {
                        try await Task.sleep(for: .milliseconds(16))
                        let image = snapshot()
                        XCTAssertTrue(range.contains(try strength(image, at: point)))
                        XCTAssertTrue(orange.contains(try strength(image, at: once)))
                    }
                }

                coordinator.applyReveal(progress: 0.53, animated: false)
                let outbound = await frame(with: late, in: orange)
                XCTAssertTrue(orange.contains(try strength(outbound, at: early)))
                // On entry to the return, the outbound road must still be visible on the very first frame.
                try await assertFrames(keeping: late, in: orange, after: 0.54)
                coordinator.applyReveal(progress: 0.76, animated: false)
                let returning = await frame(with: late, in: violet)
                XCTAssertTrue(orange.contains(try strength(returning, at: early)))
                XCTAssertTrue(violet.contains(try strength(returning, at: bend)))
                coordinator.applyReveal(progress: 0.86, animated: false)
                _ = await frame(with: early, in: violet)
                // Entering a new road must not briefly erase the completed return.
                try await assertFrames(keeping: early, in: violet, after: 0.88)

                coordinator.finishReveal()
                for zoom in [16.0, 18.0] {
                    map.setCenter(center, zoomLevel: zoom, animated: false)
                    let finished = await frame(with: early, in: violet)
                    XCTAssertTrue(orange.contains(try strength(finished, at: once)))
                    XCTAssertTrue(violet.contains(try strength(finished, at: bend)))
                    XCTAssertEqual(try strength(finished, at: beside), 0, accuracy: 0.08)
                }

                coordinator.parent.plan = plan(road: false)
                coordinator.update(map)
                coordinator.finishReveal()
                let fallback = await frame(with: early, in: orange)
                XCTAssertTrue(orange.contains(try strength(fallback, at: late)))
            }
        }
    }

    func testShortRepeatedRoadChangesOnlyAtSecondPassOnLongRoute() async throws {
        try await withMap { container in
            container.overrideUserInterfaceStyle = .light
            let map = container.map
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in map.style != nil }, object: nil)
            await fulfillment(of: [ready], timeout: 5)
            let style = try XCTUnwrap(map.style)
            let background = MLNBackgroundStyleLayer(identifier: "paper")
            background.backgroundColor = NSExpression(forConstantValue: UIColor.white)
            style.addLayer(background)
            let origin = MKMapPoint(ShoppingCoordinate.defaultOrigin.clCoordinate)
            let metersPerUnit = MKMetersPerMapPointAtLatitude(ShoppingCoordinate.defaultOrigin.latitude)
            func point(_ x: Double, _ y: Double = 0) -> ShoppingCoordinate {
                let coordinate = MKMapPoint(x: origin.x + x / metersPerUnit, y: origin.y + y / metersPerUnit).coordinate
                return ShoppingCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }

            let coordinator = RouteMapView.Coordinator(RouteMapView(origin: point(-1000)))
            coordinator.mapView = map
            coordinator.mapView(map, didFinishLoading: style)
            for meters in [4.0, 8.0] {
                let points = [point(-1000), point(0), point(meters), point(0), point(0, -1014.7)]
                coordinator.parent.plan = ShoppingPlan(id: UUID(), total: 100, savings: nil, totalSeconds: 500,
                    walkingMeters: 2040, stops: [], points: points, usesRoadNetwork: true, isSynthetic: false)
                coordinator.update(map)
                coordinator.cancelReveal()
                map.setCenter(point(meters / 2).clCoordinate, zoomLevel: 20, animated: false)
                let total = 2014.7 + 2 * meters
                let turn = (1000 + meters) / total
                let halfwayBack = (1000 + 1.5 * meters) / total
                let orange = 0.45...1.0, violet = -1.0 ... -0.15

                @MainActor func check(_ progress: Double, nearTurn: ClosedRange<Double>,
                                      nearJunction: ClosedRange<Double>) async {
                    coordinator.applyReveal(progress: progress, animated: false)
                    let painted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        let image = UIGraphicsImageRenderer(bounds: map.bounds).image { _ in
                            container.drawHierarchy(in: map.bounds, afterScreenUpdates: true)
                        }
                        @MainActor func strength(_ distance: Double) -> Double {
                            let pixel = map.convert(point(distance).clCoordinate, toPointTo: map)
                            return (try? self.orangeStrength(in: image, at: pixel)) ?? .nan
                        }
                        return nearTurn.contains(strength(meters * 0.75))
                            && nearJunction.contains(strength(meters * 0.25))
                            && orange.contains(strength(-1))
                    }, object: nil)
                    await fulfillment(of: [painted], timeout: 4)
                }
                await check(turn, nearTurn: orange, nearJunction: orange)
                await check(halfwayBack, nearTurn: violet, nearJunction: orange)
                await check(1, nearTurn: violet, nearJunction: violet)
            }
        }
    }

    private func orangeStrength(in image: UIImage, at point: CGPoint) throws -> Double {
        let rect = CGRect(x: floor(point.x * image.scale), y: floor(point.y * image.scale), width: 1, height: 1)
        let sample = try XCTUnwrap(image.cgImage?.cropping(to: rect))
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                  bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (Double(rgba[0]) - Double(rgba[2])) / 255
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
