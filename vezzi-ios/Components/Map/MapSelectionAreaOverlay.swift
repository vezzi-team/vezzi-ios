import MapLibre
import SwiftUI

/// Static map geometry and a tiny repeating texture; no per-frame overlay redraws.
@MainActor
enum MapSelectionAreaOverlay {
    static func install(in style: MLNStyle, area: LocationSelectionArea, traits: UITraitCollection) {
        let boundary = area.boundary(vertexCount: Const.vertexCount).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let hole = MLNPolygon(coordinates: boundary, count: UInt(boundary.count))
        let world = [CLLocationCoordinate2D(latitude: -Const.mercatorLatitude, longitude: -180),
                     CLLocationCoordinate2D(latitude: -Const.mercatorLatitude, longitude: 180),
                     CLLocationCoordinate2D(latitude: Const.mercatorLatitude, longitude: 180),
                     CLLocationCoordinate2D(latitude: Const.mercatorLatitude, longitude: -180),
                     CLLocationCoordinate2D(latitude: -Const.mercatorLatitude, longitude: -180)]
        let outside = MLNPolygon(coordinates: world, count: UInt(world.count), interiorPolygons: [hole])
        let source = MLNShapeSource(identifier: Const.sourceID, shape: outside, options: nil)
        style.addSource(source)
        let color = UIColor(Color.Label.secondary).resolvedColor(with: traits)
        style.setImage(hatchImage(color: color), forName: Const.patternID)
        let fill = MLNFillStyleLayer(identifier: Const.fillID, source: source)
        fill.fillPattern = NSExpression(forConstantValue: Const.patternID)
        style.addLayer(fill)

        let borderSource = MLNShapeSource(identifier: Const.borderSourceID,
                                         shape: MLNPolyline(coordinates: boundary, count: UInt(boundary.count)), options: nil)
        style.addSource(borderSource)
        let border = MLNLineStyleLayer(identifier: Const.borderID, source: borderSource)
        border.lineColor = NSExpression(forConstantValue: color)
        border.lineWidth = NSExpression(forConstantValue: Const.borderWidth)
        border.lineDashPattern = NSExpression(forConstantValue: Const.dashPattern)
        style.addLayer(border)
    }

    private static func hatchImage(color: UIColor) -> UIImage {
        let size = Const.patternSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = Const.patternScale
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { renderer in
            let context = renderer.cgContext
            context.setStrokeColor(color.withAlphaComponent(Const.hatchOpacity).cgColor)
            context.setLineWidth(Const.hatchWidth)
            for offset in [-size, .zero, size] {
                context.move(to: CGPoint(x: offset, y: size))
                context.addLine(to: CGPoint(x: offset + size, y: .zero))
            }
            context.strokePath()
        }
    }

    private enum Const {
        static let sourceID = "selection-area-outside"
        static let fillID = "selection-area-hatching"
        static let patternID = "selection-area-pattern"
        static let borderSourceID = "selection-area-boundary-source"
        static let borderID = "selection-area-boundary"
        static let vertexCount = 128
        static let mercatorLatitude = 85.05112878
        static let patternSize: CGFloat = 16
        static let patternScale: CGFloat = 2
        static let hatchWidth: CGFloat = 1.5
        static let hatchOpacity = 0.35
        static let borderWidth = 1.5
        static let dashPattern = [3, 3]
    }
}
