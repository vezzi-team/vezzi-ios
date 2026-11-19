import Foundation

/// Matches MapLibre's line-progress distance in Web Mercator, independently of vertex density.
nonisolated struct RouteRevealGeometry {
    let canAnimate: Bool
    let stopProgress: [Double]

    init(points: [ShoppingCoordinate], stops: [ShoppingCoordinate]) {
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
    }

    private struct Point {
        var x: Double
        var y: Double

        init(x: Double, y: Double) { self.x = x; self.y = y }

        init(_ coordinate: ShoppingCoordinate) {
            let latitude = min(85.05112878, max(-85.05112878, coordinate.latitude)) * .pi / 180
            x = (coordinate.longitude + 180) / 360
            y = (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2
        }

        func distance(to other: Self) -> Double { hypot(x - other.x, y - other.y) }
    }
}
