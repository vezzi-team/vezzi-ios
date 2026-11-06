import SwiftUI
import UIKit

/// Core Animation owns playback. SwiftUI updates only when the requested emotion or visibility changes.
final class MotiAnimationView: UIView {
    private let canvas = CALayer()
    private let mascot = CALayer()
    private var features: [MotiFaceGeometry.Part: CAShapeLayer] = [:]
    private var requestedState: MotiMascotView.State = .idle
    private var animates = false
    private var hasPose = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        configureLayers()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = MotiFaceGeometry.canvasSize
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.position = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        render(animates: animates && window != nil)
    }

    func update(state: MotiMascotView.State, animates: Bool) {
        guard !hasPose || requestedState != state || self.animates != animates else { return }
        requestedState = state
        self.animates = animates
        render(animates: animates && window != nil)
    }

    func stop() {
        mascot.removeAllAnimations()
        features.values.forEach { $0.removeAllAnimations() }
    }

    // MARK: - Drawing

    private func configureLayers() {
        canvas.bounds = CGRect(origin: .zero, size: MotiFaceGeometry.canvasSize)
        layer.addSublayer(canvas)
        mascot.frame = canvas.bounds
        canvas.addSublayer(mascot)
        let artwork = CALayer()
        artwork.frame = MotiFaceGeometry.artworkFrame
        artwork.contents = UIImage.Brand.motiYarn?.cgImage
        artwork.contentsGravity = .resizeAspect
        mascot.addSublayer(artwork)
        for part in MotiFaceGeometry.Part.allCases {
            let feature = CAShapeLayer()
            feature.frame = canvas.bounds
            feature.fillColor = part.isBrow ? nil : color(for: part)
            feature.strokeColor = part.isBrow ? color(for: part) : nil
            feature.lineWidth = MotiFaceGeometry.browWidth(for: MotiPose())
            feature.lineCap = .round
            feature.lineJoin = .round
            mascot.addSublayer(feature)
            features[part] = feature
        }
    }

    private func color(for part: MotiFaceGeometry.Part) -> CGColor {
        switch part {
        case .leftCheek, .rightCheek, .tongue: return UIColor(Color.Mascot.cheek).cgColor
        case .leftHighlight, .rightHighlight: return UIColor(Color.Mascot.highlight).cgColor
        default: return UIColor(Color.Mascot.ink).cgColor
        }
    }

    // MARK: - Continuous transitions

    private func render(animates: Bool) {
        let motion = MotiMotion(state: requestedState)
        let transition = animates && hasPose ? Const.transitionDuration : .zero
        let start = CACurrentMediaTime()
        let visibleTransform = mascot.presentation()?.transform ?? mascot.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (part, feature) in features {
            // Capture presentation values before removing animations, including interrupted blinks.
            let visiblePath = feature.presentation()?.path ?? feature.path
            let visibleOpacity = feature.presentation()?.opacity ?? feature.opacity
            let visibleLineWidth = feature.presentation()?.lineWidth ?? feature.lineWidth
            feature.removeAllAnimations()
            feature.path = MotiFaceGeometry.path(for: part, pose: motion.restingPose)
            feature.opacity = MotiFaceGeometry.opacity(for: part, pose: motion.restingPose)
            if part.isBrow {
                feature.lineWidth = MotiFaceGeometry.browWidth(for: motion.restingPose)
            }
            if transition > .zero {
                morph(feature, key: "path", from: visiblePath, to: feature.path, duration: transition)
                morph(feature, key: "opacity", from: visibleOpacity, to: feature.opacity, duration: transition)
                if part.isBrow {
                    morph(feature, key: "lineWidth", from: visibleLineWidth, to: feature.lineWidth,
                          duration: transition)
                }
            }
            if animates {
                let paths = motion.frames.map { MotiFaceGeometry.path(for: part, pose: $0.pose) }
                let opacities = motion.frames.map { MotiFaceGeometry.opacity(for: part, pose: $0.pose) }
                if paths.dropFirst().contains(where: { $0 != paths[0] }) {
                    animate(feature, key: "path", values: paths, motion: motion, start: start + transition)
                }
                if opacities.dropFirst().contains(where: { $0 != opacities[0] }) {
                    animate(feature, key: "opacity", values: opacities, motion: motion, start: start + transition)
                }
            }
        }
        mascot.removeAllAnimations()
        mascot.transform = transform(for: motion.restingPose)
        if transition > .zero {
            morph(mascot, key: "transform", from: NSValue(caTransform3D: visibleTransform),
                  to: NSValue(caTransform3D: mascot.transform), duration: transition)
        }
        if animates {
            animate(mascot, key: "transform",
                    values: motion.frames.map { NSValue(caTransform3D: transform(for: $0.pose)) },
                    motion: motion, start: start + transition)
        }
        hasPose = true
        CATransaction.commit()
    }

    private func morph(_ layer: CALayer, key: String, from: Any?, to: Any?, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.preferredFrameRateRange = Const.frameRateRange
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: key + ".transition")
    }

    private func animate(_ layer: CALayer, key: String, values: [Any], motion: MotiMotion, start: TimeInterval) {
        let animation = CAKeyframeAnimation(keyPath: key)
        animation.values = values
        animation.keyTimes = motion.frames.map { NSNumber(value: $0.time / motion.duration) }
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                          count: motion.frames.count - 1)
        animation.beginTime = layer.convertTime(start, from: nil)
        animation.duration = motion.duration
        animation.preferredFrameRateRange = Const.frameRateRange
        animation.repeatCount = motion.repeats ? .infinity : .zero
        // No backwards fill: the transition owns the property until the gesture starts.
        animation.fillMode = .removed
        layer.add(animation, forKey: key + ".gesture")
    }

    private func transform(for pose: MotiPose) -> CATransform3D {
        var transform = CATransform3DMakeTranslation(0, -pose.lift, 0)
        transform = CATransform3DRotate(transform, pose.tilt * .pi / Const.halfTurn, 0, 0, 1)
        return CATransform3DScale(transform, pose.stretch, 1 / pose.stretch, 1)
    }

    private enum Const {
        static let transitionDuration: TimeInterval = 0.26
        static let halfTurn: CGFloat = 180
        static let frameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    }
}
