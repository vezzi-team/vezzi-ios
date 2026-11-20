import MapLibre
import SwiftUI

@MainActor
final class RouteLineRenderer {
    static let sourceID = "polka-route"

    private let source: MLNShapeSource
    private let repeatedSource: MLNShapeSource
    private let baseLayers: [(layer: MLNLineStyleLayer, color: NSExpression)]
    private var sections: [RouteRevealGeometry.RepeatedSection] = []
    private var completeLines: [MLNPolyline] = []
    private var completedCount = 0
    private var highlightedProgress: Double = 0

    // Avoid isolated destruction on the older iOS 26 Swift runtime (as in AppRouter).
    nonisolated deinit {}

    init(style: MLNStyle, traits: UITraitCollection) {
        var options: [MLNShapeSourceOption: Any] = [.maximumZoomLevel: 22, .simplificationTolerance: 0]
        repeatedSource = MLNShapeSource(identifier: "polka-route-repeated", shape: nil, options: options)
        options[.lineDistanceMetrics] = true
        source = MLNShapeSource(identifier: Self.sourceID, shape: nil, options: options)
        style.addSource(source)
        style.addSource(repeatedSource)

        func addLine(_ id: String, source: MLNShapeSource, width: Int, color: Color) -> (MLNLineStyleLayer, NSExpression) {
            let paint = NSExpression(forConstantValue: UIColor(color).resolvedColor(with: traits))
            let layer = MLNLineStyleLayer(identifier: id, source: source)
            layer.lineWidth = NSExpression(forConstantValue: width)
            layer.lineColor = paint
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
            return (layer, paint)
        }
        baseLayers = [
            addLine("polka-route-halo", source: source, width: 9, color: Color.Label.white),
            addLine("polka-route-line", source: source, width: 5, color: Color.Map.route)
        ]
        _ = addLine("polka-route-repeated-line", source: repeatedSource, width: 5, color: Color.Map.repeatedRoute)
    }

    func setRoute(_ points: [ShoppingCoordinate], repeatedSections: [RouteRevealGeometry.RepeatedSection]) {
        source.shape = points.count >= 2 ? Self.polyline(points.map(\.clCoordinate)) : nil
        sections = repeatedSections
        completeLines = sections.map { Self.polyline($0.vertices.map { $0.coordinate.clCoordinate }) }
        completedCount = 0
        highlightedProgress = 0
        repeatedSource.shape = nil
    }

    func reveal(to progress: Double) {
        let cutoff = NSExpression(forConstantValue: [progress: UIColor.clear])
        for (layer, color) in baseLayers {
            layer.lineGradient = progress >= 1 ? color
                : NSExpression(forMLNStepping: .lineProgressVariable, from: color, stops: cutoff)
        }

        updateRepeatedRoads(at: progress)
    }

    // A single snapshot keeps the previously highlighted roads visible while the tip advances.
    private func updateRepeatedRoads(at progress: Double) {
        guard !sections.isEmpty else { return }
        if progress < highlightedProgress { completedCount = 0 }
        while completedCount < sections.count, sections[completedCount].progress.upperBound <= progress {
            completedCount += 1
        }
        let next = completedCount < sections.count ? sections[completedCount] : nil
        let isReturning = next.map { $0.progress.lowerBound < progress } ?? false
        let lastEnd = sections[..<completedCount].last?.progress.upperBound ?? 0
        let visibleProgress = isReturning ? progress : lastEnd
        guard visibleProgress != highlightedProgress else { return }
        highlightedProgress = visibleProgress

        var visible = Array(completeLines.prefix(completedCount))
        if let next, isReturning {
            let tip = next.tip(at: progress)
            // MapLibre copies the prefix of the immutable full line. Only the last vertex moves.
            let partial = MLNPolyline(coordinates: completeLines[completedCount].coordinates, count: UInt(tip.edgeEnd + 1))
            var coordinate = tip.coordinate.clCoordinate
            partial.replaceCoordinates(in: NSRange(location: tip.edgeEnd, length: 1), withCoordinates: &coordinate)
            visible.append(partial)
        }
        repeatedSource.shape = visible.isEmpty ? nil : MLNMultiPolyline(polylines: visible)
    }

    private static func polyline(_ coordinates: [CLLocationCoordinate2D]) -> MLNPolyline {
        MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
    }
}
