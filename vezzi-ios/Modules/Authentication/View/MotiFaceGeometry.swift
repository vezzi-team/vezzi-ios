import CoreGraphics
import Foundation

/// A continuous face rig. Every pose uses the same path topology, including closed eyelids.
struct MotiPose {
    var gazeX: CGFloat = 0
    var gazeY: CGFloat = 0
    var leftEye: CGFloat = 1
    var rightEye: CGFloat = 1
    var eyeSmile: CGFloat = 0
    var smile: CGFloat = 0.85
    var mouthOpen: CGFloat = 0
    var brows: CGFloat = 0
    var tilt: CGFloat = 0
    var lift: CGFloat = 0
    var stretch: CGFloat = 1
    var isTyping = false
}

enum MotiFaceGeometry {
    static let canvasSize = CGSize(width: 400, height: 280)
    static let artworkFrame = CGRect(x: 12.5, y: 8.5, width: 375, height: 263)

    enum Part: CaseIterable {
        case leftCheek, rightCheek, leftEye, rightEye
        case leftHighlight, rightHighlight, mouth, tongue, leftBrow, rightBrow

        var isBrow: Bool { self == .leftBrow || self == .rightBrow }
    }

    static func path(for part: Part, pose: MotiPose) -> CGPath {
        let path: CGPath
        switch part {
        case .leftCheek:
            path = pose.isTyping
                ? ellipse(x: 30.02, y: 116.57, width: 19.13, height: 10.94, angle: -6.18)
                : ellipse(x: 33, y: 115, width: 21.5, height: 12.5)
        case .rightCheek:
            path = pose.isTyping
                ? ellipse(x: 172.67, y: 91.77, width: 17.57, height: 10.54, angle: -24.36)
                : ellipse(x: 169.5, y: 76, width: 19.5, height: 12.5)
        case .leftEye, .rightEye:
            let left = part == .leftEye
            path = eye(open: left ? pose.leftEye : pose.rightEye, smile: pose.eyeSmile,
                       metrics: eyeMetrics(left: left, pose: pose))
        case .leftHighlight, .rightHighlight:
            let left = part == .leftHighlight
            let open = left ? pose.leftEye : pose.rightEye
            let metrics = eyeMetrics(left: left, pose: pose)
            path = ellipse(x: metrics.center.x + metrics.highlightOffset.x + pose.gazeX * 2,
                           y: metrics.center.y + metrics.highlightOffset.y * open + pose.gazeY * 5,
                           width: metrics.highlightSize.width,
                           height: max(0.1, metrics.highlightSize.height * open), angle: metrics.angle)
        case .mouth: path = mouth(pose)
        case .tongue:
            path = ellipse(x: 105, y: 107 + 13 * pose.mouthOpen,
                           width: 12 * pose.mouthOpen, height: 4 * pose.mouthOpen)
        case .leftBrow, .rightBrow:
            path = brow(left: part == .leftBrow, pose: pose)
        }
        var placement = CGAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5, tx: 122.5, ty: 106)
        return path.copy(using: &placement) ?? path
    }

    static func opacity(for part: Part, pose: MotiPose) -> Float {
        switch part {
        case .leftCheek, .rightCheek: return 0.86
        case .leftHighlight: return Float(max(0, (pose.leftEye - 0.15) / 0.85))
        case .rightHighlight: return Float(max(0, (pose.rightEye - 0.15) / 0.85))
        case .tongue: return Float(max(0, (pose.mouthOpen - 0.45) / 0.55))
        case .leftBrow, .rightBrow: return Float(pose.brows)
        default: return 1
        }
    }

    static func browWidth(for pose: MotiPose) -> CGFloat {
        pose.isTyping ? 4.0625 : 2.5
    }

    private struct EyeMetrics {
        var center: CGPoint
        let width: CGFloat
        let height: CGFloat
        let angle: CGFloat
        let highlightOffset: CGPoint
        let highlightSize: CGSize
    }

    private static func eyeMetrics(left: Bool, pose: MotiPose) -> EyeMetrics {
        var metrics: EyeMetrics
        if pose.isTyping {
            // Typing.svg uses a 79 × 58 canvas; multiply by 2.5 to match the face rig.
            metrics = EyeMetrics(center: left ? CGPoint(x: 62.18, y: 88.13) : CGPoint(x: 143.64, y: 71.50),
                                 width: left ? 15.68 : 14.71, height: left ? 19.08 : 20.97,
                                 angle: left ? -14.4 : 9.28,
                                 highlightOffset: left ? CGPoint(x: 5.62, y: 9.86) : CGPoint(x: 2.74, y: 11.89),
                                 highlightSize: CGSize(width: 3.93, height: 4.77))
        } else {
            metrics = EyeMetrics(center: CGPoint(x: left ? 53.6 : 134.4, y: left ? 73.1 : 49.9),
                                 width: 14, height: 20.5, angle: -16,
                                 highlightOffset: CGPoint(x: 4, y: -11),
                                 highlightSize: CGSize(width: 3.2, height: 4.2))
        }
        metrics.center.x += pose.gazeX * 6
        metrics.center.y += pose.gazeY * 5
        return metrics
    }

    private static func eye(open: CGFloat, smile: CGFloat, metrics: EyeMetrics) -> CGPath {
        let width = metrics.width
        let height = 1.8 + (metrics.height - 1.8) * open
        let curve = (1 - open) * (4 - 12 * smile)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width, y: 0))
        path.addCurve(to: CGPoint(x: 0, y: -height + curve),
                      control1: CGPoint(x: -width, y: -height * 0.55 + curve),
                      control2: CGPoint(x: -width * 0.55, y: -height + curve))
        path.addCurve(to: CGPoint(x: width, y: 0),
                      control1: CGPoint(x: width * 0.55, y: -height + curve),
                      control2: CGPoint(x: width, y: -height * 0.55 + curve))
        path.addCurve(to: CGPoint(x: 0, y: height + curve),
                      control1: CGPoint(x: width, y: height * 0.55 + curve),
                      control2: CGPoint(x: width * 0.55, y: height + curve))
        path.addCurve(to: CGPoint(x: -width, y: 0),
                      control1: CGPoint(x: -width * 0.55, y: height + curve),
                      control2: CGPoint(x: -width, y: height * 0.55 + curve))
        path.closeSubpath()
        return placed(path, at: metrics.center, angle: metrics.angle)
    }

    private static func mouth(_ pose: MotiPose) -> CGPath {
        let width: CGFloat = pose.isTyping ? 19.51 : (pose.smile < 0 ? 19 : 25)
        let thickness: CGFloat = pose.isTyping ? 4.0625 : 4.5
        let curve = pose.smile * 18 * (1 - pose.mouthOpen * 0.8)
        let lowerCurve = curve + pose.mouthOpen * 36
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width, y: -thickness))
        path.addCurve(to: CGPoint(x: width, y: -thickness),
                      control1: CGPoint(x: -width * 0.55, y: curve - thickness),
                      control2: CGPoint(x: width * 0.55, y: curve - thickness))
        path.addCurve(to: CGPoint(x: width, y: thickness),
                      control1: CGPoint(x: width + thickness, y: -thickness),
                      control2: CGPoint(x: width + thickness, y: thickness))
        path.addCurve(to: CGPoint(x: -width, y: thickness),
                      control1: CGPoint(x: width * 0.65, y: lowerCurve + thickness),
                      control2: CGPoint(x: -width * 0.65, y: lowerCurve + thickness))
        path.addCurve(to: CGPoint(x: -width, y: -thickness),
                      control1: CGPoint(x: -width - thickness, y: thickness),
                      control2: CGPoint(x: -width - thickness, y: -thickness))
        path.closeSubpath()
        let center = pose.isTyping ? CGPoint(x: 106.47, y: 109.52) : CGPoint(x: 104.5, y: 98)
        return placed(path, at: center, angle: pose.isTyping ? -11.26 : -16)
    }

    private static func brow(left: Bool, pose: MotiPose) -> CGPath {
        let path = CGMutablePath()
        if pose.isTyping {
            // Cubic contours from the supplied typing expression, in the rig's coordinates.
            path.move(to: left ? CGPoint(x: 19.6265, y: 55.9615) : CGPoint(x: 127.5708, y: 24.7731))
            path.addCurve(to: left ? CGPoint(x: 53.9723, y: 40.7233) : CGPoint(x: 163.8793, y: 21.916),
                          control1: left ? CGPoint(x: 27.477, y: 43.5805) : CGPoint(x: 137.384, y: 16.2017),
                          control2: left ? CGPoint(x: 39.2528, y: 37.8663) : CGPoint(x: 152.1035, y: 14.297))
            return path
        }
        // Brows remain anchored while the pupils look around.
        let center = CGPoint(x: left ? 53.6 : 134.4, y: left ? 73.1 : 49.9)
        let sad = pose.smile < 0 ? pose.brows * 8 : 0
        path.move(to: CGPoint(x: -12, y: left ? -28 : -28 - sad))
        path.addCurve(to: CGPoint(x: 12, y: left ? -28 - sad : -28),
                      control1: CGPoint(x: -5, y: -32 - sad),
                      control2: CGPoint(x: 5, y: -32 - sad))
        return placed(path, at: center)
    }

    private static func ellipse(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                                angle: CGFloat = -16) -> CGPath {
        // Keep four cubic segments even when an invisible tongue or highlight collapses.
        let width = max(0.01, width)
        let height = max(0.01, height)
        let path = CGPath(ellipseIn: CGRect(x: -width, y: -height, width: width * 2, height: height * 2),
                          transform: nil)
        return placed(path, at: CGPoint(x: x, y: y), angle: angle)
    }

    private static func placed(_ path: CGPath, at center: CGPoint, angle: CGFloat = -16) -> CGPath {
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: .pi * angle / 180)
        return path.copy(using: &transform) ?? path
    }
}
