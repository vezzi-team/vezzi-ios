import MapLibre
import SwiftUI
import UIKit

/// Keeps the pin and radius in map coordinates without publishing per-frame SwiftUI state.
@MainActor
final class MapPointSelection {
    private let overlay = UIView()
    private let circle = CAShapeLayer()
    private let pin = UIImageView(image: UIImage.System.startPin)
    private var viewportInsets = UIEdgeInsets.zero
    private(set) var cameraInsets = UIEdgeInsets.zero
    private var appliedInsets: UIEdgeInsets?
    private var appliedSize = CGSize.zero
    private var radiusMeters: Int?
    private var renderedRadiusMeters: Int?
    private var hasRendered = false
    private var returnsToStart = false
    private var lastInput: ShoppingCoordinate?
    private(set) var selectedCoordinate: ShoppingCoordinate?
    private var needsCameraUpdate = false
    private var preservesUserCamera = false
    private var isAnimating = false
    private var targetZoom: Double?
    private var cameraRevision = UUID()
    private var canAnimate = false
    private(set) var isAdjustingCamera = false

    func install(in container: UIView) {
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = true
        container.addSubview(overlay)
        overlay.layer.addSublayer(circle)
        overlay.addSubview(pin)
        pin.contentMode = .scaleAspectFit
        pin.bounds.size = CGSize(width: Const.pinWidth, height: Const.pinHeight)
        pin.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        pin.isAccessibilityElement = true
        pin.accessibilityLabel = Texts.Routes.yourStart
        pin.accessibilityHint = Texts.Routes.Settings.moveMap
        pin.accessibilityIdentifier = AccessibilityID.Routes.Settings.pin
        circle.lineWidth = Const.borderWidth
        circle.opacity = .zero
    }

    @discardableResult
    func update(_ map: MLNMapView, coordinate: ShoppingCoordinate, radius: Int?, returnsToStart: Bool, bottomInset: CGFloat,
                liveBottomInset: CGFloat, isInteracting: Bool, animated: Bool) -> ShoppingCoordinate? {
        guard map.bounds.width > .zero, map.bounds.height > .zero else { return nil }
        overlay.frame = map.frame
        canAnimate = animated
        if self.returnsToStart != returnsToStart {
            self.returnsToStart = returnsToStart
            if let image = returnsToStart ? UIImage.System.roundTripPin : UIImage.System.startPin {
                if hasRendered, canAnimate {
                    pin.setSymbolImage(image, contentTransition: .replace, options: .speed(Const.pinTransitionSpeed))
                } else {
                    pin.image = image
                }
            }
        }
        if !canAnimate {
            pin.removeAllSymbolEffects(animated: false)
            pin.layer.removeAllAnimations()
            circle.removeAllAnimations()
        }
        viewportInsets = insets(for: map, bottomInset: liveBottomInset)
        cameraInsets = insets(for: map, bottomInset: bottomInset)
        if lastInput != coordinate {
            lastInput = coordinate
            if selectedCoordinate != coordinate {
                preservesUserCamera = isInteracting
                needsCameraUpdate = !isInteracting
            }
            selectedCoordinate = coordinate
            pin.accessibilityValue = Texts.Routes.coordinate(coordinate)
        }
        if radiusMeters != radius {
            updateRadius(radius)
            radiusMeters = radius
            preservesUserCamera = isInteracting
            needsCameraUpdate = !isInteracting
        }
        let viewportChanged = appliedInsets != cameraInsets || appliedSize != map.bounds.size
        if preservesUserCamera {
            render(map)
            // Live panel measurements move only the pin. Publish once its viewport settles.
            if !isInteracting, viewportChanged, viewportInsets == cameraInsets {
                let previous = selectedCoordinate
                let settled = settle(map)
                return settled != previous ? settled : nil
            }
            return nil
        }
        if viewportChanged || (isAnimating && !canAnimate) {
            needsCameraUpdate = true
        }
        if !isInteracting { updateCameraIfNeeded(map) }
        render(map)
        return nil
    }

    func render(_ map: MLNMapView) {
        let area = map.bounds.inset(by: viewportInsets)
        let anchor = CGPoint(x: area.midX, y: area.midY)
        let coordinate = map.convert(anchor, toCoordinateFrom: map)
        overlay.isHidden = area.height < Const.minimumMapHeight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        move(pin.layer, to: anchor)
        move(circle, to: anchor)
        pin.tintColor = UIColor(Color.Map.route)
        let metersPerPoint = map.metersPerPoint(atLatitude: coordinate.latitude)
        if let radiusMeters = renderedRadiusMeters, metersPerPoint.isFinite, metersPerPoint > .zero {
            let radius = CGFloat(Double(radiusMeters) / metersPerPoint)
            circle.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius,
                                                  width: radius * 2, height: radius * 2), transform: nil)
            circle.fillColor = UIColor(Color.Map.route).withAlphaComponent(Const.fillOpacity).cgColor
            circle.strokeColor = UIColor(Color.Map.route).withAlphaComponent(Const.strokeOpacity).cgColor
        } else {
            circle.path = nil
        }
        CATransaction.commit()
        hasRendered = true
    }

    private func move(_ layer: CALayer, to position: CGPoint) {
        guard layer.position != position else { return }
        animate(layer, keyPath: "position", to: NSValue(cgPoint: position))
    }

    private func updateRadius(_ radius: Int?) {
        // The path follows camera zoom; a separate scale interpolates the chosen radius.
        // Retarget from its presentation value so quick selections do not jump.
        if let radius {
            let scale = circle.presentation()?.transform.m11 ?? 1
            let previous = Double(renderedRadiusMeters ?? radius) * Double(scale)
            renderedRadiusMeters = radius
            animate(circle, keyPath: "transform.scale", from: previous / Double(radius), to: 1)
        }
        animate(circle, keyPath: "opacity", to: radius == nil ? 0 : 1)
    }

    private func animate(_ layer: CALayer, keyPath: String, from: Any? = nil, to value: Any) {
        let current = from ?? (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        guard hasRendered, canAnimate else { layer.removeAnimation(forKey: keyPath); return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = current
        animation.toValue = value
        animation.duration = Const.cameraDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: keyPath)
    }

    /// Commit the final pin position without replaying a fit cancelled by the gesture.
    func settle(_ map: MLNMapView) -> ShoppingCoordinate? {
        guard lastInput != nil, map.bounds.width > .zero, map.bounds.height > .zero else { return nil }
        let point = map.convert(pin.layer.position, toCoordinateFrom: map)
        let selection = ShoppingCoordinate(latitude: point.latitude, longitude: point.longitude)
        guard selection.isValid else { return nil }
        selectedCoordinate = selection
        prepareCamera(map)
        render(map)
        pin.accessibilityValue = Texts.Routes.coordinate(selection)
        return selection
    }

    func visibleCoordinate(in map: MLNMapView) -> ShoppingCoordinate {
        let anchor = pin.layer.presentation()?.position ?? pin.layer.position
        let coordinate = map.convert(anchor, toCoordinateFrom: map)
        return ShoppingCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func prepareCamera(_ map: MLNMapView) {
        // Gestures and explicit controls take ownership from automatic viewport fitting.
        preservesUserCamera = true
        needsCameraUpdate = false
        isAnimating = false
        targetZoom = nil
        cameraRevision = UUID()
        appliedInsets = cameraInsets
        appliedSize = map.bounds.size
    }

    private func updateCameraIfNeeded(_ map: MLNMapView) {
        guard needsCameraUpdate, let coordinate = selectedCoordinate, map.window != nil,
              map.bounds.inset(by: cameraInsets).height >= Const.minimumMapHeight else { return }
        let diameter = visibleDiameter(size: map.bounds.size, insets: cameraInsets)
        var zoom = map.zoomLevel
        if let radiusMeters {
            let scale = Double(diameter) * map.metersPerPoint(atLatitude: coordinate.latitude) / Double(radiusMeters * 2)
            if scale.isFinite, scale > .zero { zoom += log2(scale) }
        } else if let appliedInsets, appliedSize != .zero {
            // Keep the same geographic extent when the panel changes, even without a radius limit.
            if isAnimating, let targetZoom { zoom = targetZoom }
            zoom += log2(Double(diameter / visibleDiameter(size: appliedSize, insets: appliedInsets)))
        }
        zoom = min(map.maximumZoomLevel, max(map.minimumZoomLevel, zoom))
        let camera = map.camera
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        camera.altitude = MLNAltitudeForZoomLevel(zoom, camera.pitch, coordinate.latitude, map.bounds.size)
        let animated = appliedInsets != nil && canAnimate
        appliedInsets = cameraInsets
        appliedSize = map.bounds.size
        needsCameraUpdate = false
        isAnimating = animated
        targetZoom = zoom
        let revision = UUID()
        cameraRevision = revision
        isAdjustingCamera = true
        map.setCamera(camera, withDuration: animated ? Const.cameraDuration : .zero,
                      animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut), edgePadding: cameraInsets) { [weak self] in
            if self?.cameraRevision == revision { self?.isAnimating = false }
        }
        isAdjustingCamera = false
    }

    private func insets(for map: MLNMapView, bottomInset: CGFloat) -> UIEdgeInsets {
        let bottom = min(map.bounds.height, max(map.safeAreaInsets.bottom, bottomInset))
        let top = min(map.safeAreaInsets.top + Const.topInset,
                      max(.zero, map.bounds.height - bottom - Const.minimumMapHeight))
        return UIEdgeInsets(top: top, left: .zero, bottom: bottom, right: .zero)
    }

    private func visibleDiameter(size: CGSize, insets: UIEdgeInsets) -> CGFloat {
        max(Const.minimumMapHeight, min(size.width - insets.left - insets.right,
                                        size.height - insets.top - insets.bottom) - Const.radiusPadding * 2)
    }

    private enum Const {
        static let topInset: CGFloat = 80
        static let minimumMapHeight: CGFloat = 64
        static let radiusPadding: CGFloat = 24
        static let pinWidth: CGFloat = 44
        static let pinHeight: CGFloat = 56
        static let borderWidth: CGFloat = 2
        static let fillOpacity: CGFloat = 0.10
        static let strokeOpacity: CGFloat = 0.7
        static let cameraDuration = 0.3
        static let pinTransitionSpeed = 2.0
    }
}
