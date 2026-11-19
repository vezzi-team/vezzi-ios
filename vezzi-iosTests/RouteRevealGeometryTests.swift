import XCTest
@testable import vezzi_ios

final class RouteRevealGeometryTests: XCTestCase {
    func testStopsFollowDistanceInsteadOfVertexCount() {
        let route = RouteRevealGeometry(points: [point(0), point(9), point(10)], stops: [point(5), point(9)])
        XCTAssertTrue(route.canAnimate)
        XCTAssertEqual(route.stopProgress[0], 0.5, accuracy: 0.000001)
        XCTAssertEqual(route.stopProgress[1], 0.9, accuracy: 0.000001)
    }

    func testStopsNearTheRoadProjectOntoSegments() {
        let route = RouteRevealGeometry(points: [point(0), point(10)],
                                        stops: [ShoppingCoordinate(latitude: 0.01, longitude: 4)])
        XCTAssertEqual(route.stopProgress[0], 0.4, accuracy: 0.000001)
    }

    func testRetracedRoadKeepsStopsInVisitOrder() {
        let route = RouteRevealGeometry(points: [point(0), point(10), point(0)], stops: [point(8), point(2)])
        XCTAssertEqual(route.stopProgress[0], 0.4, accuracy: 0.000001)
        XCTAssertEqual(route.stopProgress[1], 0.9, accuracy: 0.000001)
    }

    func testRepeatedVerticesAndCoincidentStops() {
        let route = RouteRevealGeometry(points: [point(0), point(0), point(10), point(10)],
                                        stops: [point(0), point(5), point(5), point(10)])
        for (value, expected) in zip(route.stopProgress, [0, 0.5, 0.5, 1]) {
            XCTAssertEqual(value, expected, accuracy: 0.000001)
        }
    }

    func testMissingOrDegenerateGeometryShowsAllStopsImmediately() {
        for points in [[], [point(0)], [point(0), point(0)], [point(0), point(.nan)]] {
            let route = RouteRevealGeometry(points: points, stops: [point(1), point(2)])
            XCTAssertFalse(route.canAnimate)
            XCTAssertEqual(route.stopProgress, [1, 1])
        }
    }

    func testDateLineCrossingUsesShortSegment() {
        let route = RouteRevealGeometry(points: [point(179), point(-179)], stops: [point(180)])
        XCTAssertEqual(route.stopProgress[0], 0.5, accuracy: 0.000001)
    }

    private func point(_ longitude: Double) -> ShoppingCoordinate {
        ShoppingCoordinate(latitude: 0, longitude: longitude)
    }
}
