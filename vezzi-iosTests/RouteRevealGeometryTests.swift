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

    func testSecondAndLaterTraversalsStayHighlighted() throws {
        let a = point(0), b = point(1)
        let route = RouteRevealGeometry(points: [a, b, b, a, b, a], stops: [])
        XCTAssertEqual(route.repeatedSections.count, 1)
        let repeated = try XCTUnwrap(route.repeatedSections.first)
        XCTAssertEqual(repeated.progress.lowerBound, 0.25, accuracy: 1e-9)
        XCTAssertEqual(repeated.progress.upperBound, 1)
    }

    func testOnlySharedPartOfResampledRoadIsHighlighted() throws {
        let route = RouteRevealGeometry(points: [point(0), point(3), point(1), point(4)], stops: [])
        XCTAssertEqual(route.repeatedSections.count, 1)
        let repeated = try XCTUnwrap(route.repeatedSections.first)
        XCTAssertEqual(repeated.vertices.map(\.coordinate), [point(3), point(1), point(3)])
        let returning = repeated.tip(at: 0.5)
        let retracing = repeated.tip(at: 0.75)
        XCTAssertEqual(returning.edgeEnd, 1)
        XCTAssertEqual(retracing.edgeEnd, 2)
        XCTAssertEqual(returning.coordinate.longitude, 2, accuracy: 1e-9)
        XCTAssertEqual(retracing.coordinate.longitude, 2, accuracy: 1e-9)
        XCTAssertEqual(repeated.progress.lowerBound, 3.0 / 8, accuracy: 1e-9)
        XCTAssertEqual(repeated.progress.upperBound, 7.0 / 8, accuracy: 1e-9)
    }

    func testReturnRecognizesARoundedViaPointOnEitherTraversal() throws {
        let start = ShoppingCoordinate(latitude: 60.020266, longitude: 30.262163)
        let turn = ShoppingCoordinate(latitude: 60.020775, longitude: 30.263918)
        // 61% along this street, rounded to the six decimal places in the route export.
        let via = ShoppingCoordinate(latitude: 60.020576, longitude: 30.263234)

        for points in [[start, turn, via, start], [start, via, turn, start]] {
            let route = RouteRevealGeometry(points: points, stops: [])
            XCTAssertEqual(route.repeatedSections.count, 1)
            let repeated = try XCTUnwrap(route.repeatedSections.first)
            XCTAssertEqual(repeated.vertices.map(\.coordinate), [turn, via, start])
            XCTAssertEqual(repeated.progress.lowerBound, 0.5, accuracy: 1e-6)
            XCTAssertEqual(repeated.progress.upperBound, 1)
        }

        let offRoad = ShoppingCoordinate(latitude: via.latitude + 0.000003, longitude: via.longitude)
        let detour = RouteRevealGeometry(points: [start, turn, offRoad, start], stops: [])
        XCTAssertTrue(detour.repeatedSections.isEmpty)
    }

    func testRoundedViaPointsCanShareLatitudeWithTheEndsOfTheRoad() throws {
        let start = ShoppingCoordinate(latitude: 60.008683, longitude: 30.258462)
        let turn = ShoppingCoordinate(latitude: 60.008659, longitude: 30.258490)
        let nearStart = ShoppingCoordinate(latitude: start.latitude, longitude: 30.258463)
        let nearTurn = ShoppingCoordinate(latitude: turn.latitude, longitude: 30.258489)
        let route = RouteRevealGeometry(points: [start, turn, nearTurn, nearStart, start], stops: [])
        XCTAssertEqual(route.repeatedSections.count, 1)
        let repeated = try XCTUnwrap(route.repeatedSections.first)
        XCTAssertEqual(repeated.vertices.map(\.coordinate), [turn, nearTurn, nearStart, start])
        XCTAssertEqual(repeated.progress.upperBound, 1)
    }

    func testDetourSeparatesVisitsAndSameDirectionAlsoCounts() throws {
        let a = point(0), b = point(1), c = point(2), d = point(3)
        let detour = ShoppingCoordinate(latitude: 1, longitude: 1)
        let route = RouteRevealGeometry(points: [a, d, c, detour, a, b], stops: [])
        XCTAssertEqual(route.repeatedSections.count, 2)
        let first = try XCTUnwrap(route.repeatedSections.first)
        let last = try XCTUnwrap(route.repeatedSections.last)
        XCTAssertLessThan(first.progress.upperBound, last.progress.lowerBound)
        XCTAssertEqual(last.progress.upperBound, 1)
    }

    func testPartialReturnUsesTheShortWayAcrossTheDateLine() throws {
        let a = point(179), b = point(-179)
        let geometry = RouteRevealGeometry(points: [a, b, a], stops: [])
        let repeated = try XCTUnwrap(geometry.repeatedSections.first)
        XCTAssertEqual(repeated.tip(at: 0.5).coordinate, b)
        let halfway = repeated.tip(at: 0.75)
        XCTAssertEqual(halfway.edgeEnd, 1)
        XCTAssertEqual(abs(halfway.coordinate.longitude), 180, accuracy: 1e-9)
        XCTAssertEqual(repeated.tip(at: 1).coordinate, a)
    }

    func testCrossingsParallelRoadsAndFallbackGeometryAreNotHighlighted() {
        let a = point(0), b = point(0.001)
        let nearA = ShoppingCoordinate(latitude: 0.00003, longitude: a.longitude)
        let nearB = ShoppingCoordinate(latitude: 0.00003, longitude: b.longitude)
        let across = ShoppingCoordinate(latitude: -0.001, longitude: 0.0005)
        let route = RouteRevealGeometry(points: [a, b, nearB, nearA, across, a], stops: [])
        XCTAssertTrue(route.repeatedSections.isEmpty)
        XCTAssertTrue(RouteRevealGeometry(points: [a, b, a], stops: [], marksRepeatedRoads: false).repeatedSections.isEmpty)
    }

    private func point(_ longitude: Double) -> ShoppingCoordinate {
        ShoppingCoordinate(latitude: 0, longitude: longitude)
    }
}
