import Foundation

/// Matches MapLibre's line-progress distance in Web Mercator, independently of vertex density.
nonisolated struct RouteRevealGeometry {
    let canAnimate: Bool
    let stopProgress: [Double]
    private(set) var repeatedSections: [RepeatedSection] = []

    struct RepeatedSection {
        struct Vertex {
            let coordinate: ShoppingCoordinate
            let progress: Double
        }

        // Each section starts with an edge and contains at least two ordered vertices.
        fileprivate(set) var vertices: [Vertex]
        var progress: Range<Double> { vertices[0].progress..<vertices[vertices.count - 1].progress }

        func tip(at progress: Double) -> (edgeEnd: Int, coordinate: ShoppingCoordinate) {
            var low = 1, high = vertices.count - 1
            while low < high {
                let middle = low + (high - low) / 2
                if vertices[middle].progress < progress { low = middle + 1 } else { high = middle }
            }
            let start = vertices[low - 1], end = vertices[low]
            if progress <= start.progress { return (low, start.coordinate) }
            if progress >= end.progress { return (low, end.coordinate) }
            let fraction = (progress - start.progress) / (end.progress - start.progress)
            return (low, Point(start.coordinate).interpolated(to: Point(end.coordinate), fraction: fraction))
        }
    }

    init(points: [ShoppingCoordinate], stops: [ShoppingCoordinate], marksRepeatedRoads: Bool = true) {
        guard points.count > 1, points.allSatisfy(\.isValid) else {
            canAnimate = false
            stopProgress = stops.map { _ in 1 }
            return
        }
        var projected = [Point]()
        for coordinate in points {
            var point = Point(coordinate)
            if let previous = projected.last { point.x += (previous.x - point.x).rounded() }
            projected.append(point)
        }
        var distances = [0.0]
        for index in 1..<projected.count {
            distances.append(distances[index - 1] + projected[index].distance(to: projected[index - 1]))
        }
        let total = distances.last ?? 0
        canAnimate = total > 0
        guard canAnimate else {
            stopProgress = stops.map { _ in 1 }
            return
        }
        var previousProgress = 0.0
        stopProgress = stops.map { coordinate in
            guard coordinate.isValid else { return 1 }
            let point = Point(coordinate)
            var closestDistance = Double.infinity
            var progress = 1.0
            for index in 1..<projected.count {
                let start = projected[index - 1]
                let end = projected[index]
                let length = distances[index] - distances[index - 1]
                guard length > 0, distances[index] / total >= previousProgress else { continue }
                var target = point
                target.x += ((start.x + end.x) / 2 - target.x).rounded()
                let dx = end.x - start.x
                let dy = end.y - start.y
                let minimum = max(0, (previousProgress * total - distances[index - 1]) / length)
                let fraction = min(1, max(minimum, ((target.x - start.x) * dx + (target.y - start.y) * dy) / (length * length)))
                let projectedStop = Point(x: start.x + dx * fraction, y: start.y + dy * fraction)
                let distance = projectedStop.distance(to: target)
                if distance < closestDistance {
                    closestDistance = distance
                    progress = (distances[index - 1] + length * fraction) / total
                }
            }
            // A retraced road must not reveal a later stop before the preceding one.
            previousProgress = min(1, max(previousProgress, progress))
            return previousProgress
        }
        if marksRepeatedRoads {
            repeatedSections = Self.repeatedRoadSections(points, projected: projected, distances: distances, total: total)
        }
    }

    private struct RoadEdge: Hashable {
        let first: Point
        let second: Point

        init(_ a: Point, _ b: Point) {
            (first, second) = a.x < b.x || (a.x == b.x && a.y < b.y) ? (a, b) : (b, a)
        }
    }

    /// A color boundary can occur inside an edge when only one visit contains a via point.
    private static func repeatedRoadSections(_ points: [ShoppingCoordinate], projected: [Point],
                                             distances: [Double], total: Double) -> [RepeatedSection] {
        let vertices = RoadVertices(projected)
        var visited = Set<RoadEdge>()
        var sections: [RepeatedSection] = []
        for index in 1..<points.count {
            let length = distances[index] - distances[index - 1]
            guard length > 0 else { continue }
            var previous = index - 1
            var start = distances[previous] / total
            for (next, fraction) in vertices.subdivisions(from: previous, to: index) {
                let end = (next == index ? distances[index] : distances[index - 1] + length * fraction) / total
                guard end > start else { continue }
                if !visited.insert(RoadEdge(projected[previous], projected[next])).inserted {
                    let vertex = RepeatedSection.Vertex(coordinate: points[next], progress: end)
                    if let last = sections.indices.last, sections[last].progress.upperBound == start {
                        sections[last].vertices.append(vertex)
                    } else {
                        let first = RepeatedSection.Vertex(coordinate: points[previous], progress: start)
                        sections.append(RepeatedSection(vertices: [first, vertex]))
                    }
                }
                previous = next
                start = end
            }
        }
        return sections
    }

    /// A via point can subdivide a road on only one traversal. Use existing route vertices
    /// on that edge, looking up candidates along its dominant axis once per segment.
    private struct RoadVertices {
        let points: [Point]
        let byX: [Int]
        let byY: [Int]

        init(_ points: [Point]) {
            self.points = points
            var seen = Set<Point>()
            let unique = points.indices.filter { seen.insert(points[$0]).inserted }
            byX = unique.sorted { points[$0].x < points[$1].x }
            byY = unique.sorted { points[$0].y < points[$1].y }
        }

        func subdivisions(from start: Int, to end: Int) -> [(index: Int, fraction: Double)] {
            let a = points[start], b = points[end]
            let dx = b.x - a.x, dy = b.y - a.y
            let useX = abs(dx) >= abs(dy)
            let axis: KeyPath<Point, Double> = useX ? \.x : \.y
            let sorted = useX ? byX : byY
            let xBounds = min(a.x, b.x)...max(a.x, b.x)
            let yBounds = min(a.y, b.y)...max(a.y, b.y)
            let bounds = useX ? xBounds : yBounds
            // A rounded via point can share one coordinate with an endpoint.
            var low = 0, high = sorted.count
            while low < high {
                let mid = (low + high) / 2
                if points[sorted[mid]][keyPath: axis] < bounds.lowerBound { low = mid + 1 } else { high = mid }
            }
            // The via point and the edge endpoints can each round by half a microdegree on either axis.
            // Bound their combined error perpendicular to the edge. Mercator scales latitude by sec(φ).
            let coordinateStep = 0.000001 / 360
            let latitudeScale = cosh(2 * .pi * max(abs(a.y - 0.5), abs(b.y - 0.5)))
            let crossProductTolerance = coordinateStep * (abs(dy) + abs(dx) * latitudeScale)
            let lengthSquared = dx * dx + dy * dy
            var result = [(index: Int, fraction: Double)]()
            for index in sorted[low...] {
                let p = points[index]
                guard p[keyPath: axis] <= bounds.upperBound else { break }
                guard xBounds.contains(p.x), yBounds.contains(p.y) else { continue }
                let px = p.x - a.x, py = p.y - a.y
                guard abs(dx * py - dy * px) <= crossProductTolerance else { continue }
                let fraction = (dx * px + dy * py) / lengthSquared
                guard fraction > 0, fraction < 1 else { continue }
                result.append((index, fraction))
            }
            result.sort { $0.fraction < $1.fraction }
            result.append((end, 1))
            return result
        }
    }

    private struct Point: Hashable {
        var x: Double
        var y: Double

        init(x: Double, y: Double) { self.x = x; self.y = y }

        init(_ coordinate: ShoppingCoordinate) {
            let latitude = min(85.05112878, max(-85.05112878, coordinate.latitude)) * .pi / 180
            x = (coordinate.longitude + 180) / 360
            y = (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2
        }

        func interpolated(to end: Self, fraction: Double) -> ShoppingCoordinate {
            let dx = end.x - x
            let longitude = x + (dx - dx.rounded()) * fraction
            let latitude = atan(sinh(.pi * (1 - 2 * (y + (end.y - y) * fraction))))
            return ShoppingCoordinate(latitude: latitude * 180 / .pi,
                                      longitude: (longitude - floor(longitude)) * 360 - 180)
        }

        func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
    }
}
