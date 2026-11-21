import MapLibre
import SwiftUI

/// OpenStreetMap vector tiles with a small, stable set of route layers and numbered stops.
struct RouteMapView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let origin: ShoppingCoordinate
    var plan: ShoppingPlan?
    var bottomInset: CGFloat = .zero
    var cameraRequest: MapCameraRequest?
    var deviceCoordinate: ShoppingCoordinate?
    var reloadRevision = 0
    var selectionRadius: Int?
    var selectionReturnsToStart = false
    var selectionLiveBottomInset: CGFloat?
    var selectionArea: LocationSelectionArea?
    var onInteractionBegan: () -> Void = {}
    var onSelectCoordinate: ((ShoppingCoordinate) -> Void)?
    var onSelectionAvailabilityChanged: (Bool) -> Void = { _ in }
    var onLoadFailure: (Bool) -> Void = { _ in }
    var onShowAttribution: (([MapAttribution]) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MapContainerView {
        let container = MapContainerView(styleURL: styleURL)
        let map = container.map
        context.coordinator.mapView = map
        container.onLayout = { [weak coordinator = context.coordinator] in
            guard let coordinator, let map = coordinator.mapView else { return }
            coordinator.update(map)
        }
        map.delegate = context.coordinator
        map.automaticallyAdjustsContentInset = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsLogoView = false
        map.showsAttributionButton = false
        if Const.showsAttribution { context.coordinator.installAttribution(in: container) }
        map.accessibilityIdentifier = AccessibilityID.Routes.map
        map.setCenter(origin.clCoordinate, zoomLevel: Const.initialZoom, animated: false)
        if onSelectCoordinate != nil {
            let selection = MapPointSelection()
            selection.install(in: container)
            context.coordinator.pointSelection = selection
        }
        return container
    }

    func updateUIView(_ container: MapContainerView, context: Context) {
        let map = container.map
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.attributionBottom?.constant = -max(Const.ornamentInset,
                                                       bottomInset - container.safeAreaInsets.bottom + Const.ornamentInset)
        if map.styleURL != styleURL {
            coordinator.finishReveal()
            map.styleURL = styleURL
        }
        if coordinator.reloadRevision != reloadRevision {
            coordinator.reloadRevision = reloadRevision
            coordinator.finishReveal()
            map.reloadStyle(nil)
        }
        coordinator.update(map)
    }

    static func dismantleUIView(_ container: MapContainerView, coordinator: Coordinator) {
        coordinator.cancelReveal()
        container.onLayout = nil
        container.map.delegate = nil
        coordinator.mapView = nil
    }

    private var styleURL: URL {
        // OpenFreeMap supplies OSM vector tiles and includes the required source attribution.
        URL(string: "https://tiles.openfreemap.org/styles/\(colorScheme == .dark ? "dark" : "liberty")")!
    }

    /// Keep map controls beside the SDK view so its accessibility and gestures do not intercept them.
    final class MapContainerView: UIView {
        let map: MLNMapView
        var onLayout: (() -> Void)?

        init(styleURL: URL) {
            map = MLNMapView(frame: .zero, styleURL: styleURL)
            super.init(frame: .zero)
            map.translatesAutoresizingMaskIntoConstraints = false
            addSubview(map)
            NSLayoutConstraint.activate([
                map.topAnchor.constraint(equalTo: topAnchor), map.bottomAnchor.constraint(equalTo: bottomAnchor),
                map.leadingAnchor.constraint(equalTo: leadingAnchor), map.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        required init?(coder: NSCoder) { fatalError("Use init(styleURL:)") }

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: RouteMapView
        weak var mapView: MLNMapView?
        var pointSelection: MapPointSelection?
        private weak var attributionButton: UIButton?
        var attributionBottom: NSLayoutConstraint?
        var reloadRevision = 0
        private var renderedPlanID: UUID?
        private var renderedOrigin: ShoppingCoordinate?
        private var lastSize: CGSize = .zero
        private var lastInsets: UIEdgeInsets = .zero
        private var lastBottomInset: CGFloat?
        private var needsCameraFit = false
        private var hasFittedCamera = false
        private var preservesUserCamera = false
        private var isInteracting = false
        private var interactionRevision = UUID()
        private var lastSelectionAvailability: Bool?
        private var lastCameraRequestID: UUID?
        private var requestedZoom: Double?
        private var deviceAnnotation: DeviceLocationAnnotation?
        private var displayLink: CADisplayLink?
        private var revealStartedAt: CFTimeInterval = .zero
        private var routeRenderer: RouteLineRenderer?
        private var pendingStops: [(annotation: RouteAnnotation, progress: Double)] = []
        private var captionsNeedLayout = false

        init(_ parent: RouteMapView) { self.parent = parent }

        func installAttribution(in container: MapContainerView) {
            // Replace the optional SDK branding and info icon, retaining readable data credits.
            let button = UIButton(type: .system)
            attributionButton = button
            var configuration = UIButton.Configuration.plain()
            configuration.title = Texts.Routes.mapAttribution
            configuration.baseForegroundColor = UIColor(Color.Label.primary)
            configuration.background.backgroundColor = UIColor(Color.Background.secondary)
            configuration.background.cornerRadius = Const.attributionRadius
            configuration.contentInsets = .init(top: Const.attributionVerticalInset,
                                                 leading: Const.attributionHorizontalInset,
                                                 bottom: Const.attributionVerticalInset,
                                                 trailing: Const.attributionHorizontalInset)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = UIFont.preferredFont(forTextStyle: .caption2)
                return result
            }
            button.configuration = configuration
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = .zero
            button.accessibilityIdentifier = AccessibilityID.Routes.attribution
            button.accessibilityLabel = Texts.Routes.mapAttribution
            button.accessibilityHint = Texts.Routes.mapSources
            button.addTarget(self, action: #selector(showAttribution(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(button)
            let bottom = button.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor,
                                                        constant: -Const.ornamentInset)
            attributionBottom = bottom
            NSLayoutConstraint.activate([
                bottom,
                button.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -Const.ornamentInset),
                button.leadingAnchor.constraint(greaterThanOrEqualTo: container.safeAreaLayoutGuide.leadingAnchor, constant: Const.ornamentInset)
            ])
        }

        @objc func showAttribution(_ sender: UIButton) {
            guard let map = mapView else { return }
            guard let showAttribution = parent.onShowAttribution else {
                map.showAttribution(sender)
                return
            }
            let infos = (map.style?.sources ?? []).compactMap { $0 as? MLNTileSource }.flatMap(\.attributionInfos)
            var seen = Set<String>()
            let values = infos.map { MapAttribution(title: $0.title.string, url: $0.url) }
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.title < $1.title }
            // Source metadata may still be loading; this provider's credits are known in advance.
            showAttribution(values.isEmpty ? MapAttribution.openFreeMap : values)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            if let area = parent.selectionArea {
                MapSelectionAreaOverlay.install(in: style, area: area, traits: mapView.traitCollection)
            }
            routeRenderer = RouteLineRenderer(style: style, traits: mapView.traitCollection)
            update(mapView, styleReloaded: true)
            notifyFailure(false)
        }

        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: any Error) {
            notifyFailure(true)
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            // Tap recognizers have already ended when the SDK starts their zoom animation.
            let isTapZoom = !reason.intersection([.gestureZoomIn, .gestureZoomOut]).isEmpty
            guard !reason.intersection(Const.userGestures).isEmpty,
                  isTapZoom || hasActiveGesture(mapView) else { return }
            isInteracting = true
            interactionRevision = UUID()
            lastSelectionAvailability = nil
            requestedZoom = nil
            lastCameraRequestID = parent.cameraRequest?.id
            preservesUserCamera = true
            needsCameraFit = false
            pointSelection?.prepareCamera(mapView)
            parent.onInteractionBegan()
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            guard pointSelection?.isAdjustingCamera != true else { return }
            if let pointSelection {
                // Layout, style loading and centering must not turn a confirmed point into a new draft.
                guard isInteracting, !hasActiveGesture(mapView) else { return }
                let revision = interactionRevision
                // Avoid publishing during updateUIView or recursively from setCenter/contentInset.
                Task { @MainActor [weak self] in
                    guard let self, self.interactionRevision == revision, let map = self.mapView,
                          self.isInteracting, !self.hasActiveGesture(map) else { return }
                    self.isInteracting = false
                    guard let coordinate = pointSelection.settle(map) else { return }
                    self.parent.onSelectCoordinate?(coordinate)
                    self.applyCameraRequest(map)
                }
                return
            }
            guard isInteracting, !hasActiveGesture(mapView) else { return }
            isInteracting = false
            applyCameraRequest(mapView)
        }

        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            pointSelection?.render(mapView)
            if isInteracting, let selection = pointSelection, let area = parent.selectionArea {
                let available = area.contains(selection.visibleCoordinate(in: mapView))
                if lastSelectionAvailability != available {
                    lastSelectionAvailability = available
                    Task { @MainActor [weak self] in
                        guard let self, self.isInteracting, self.lastSelectionAvailability == available else { return }
                        self.parent.onSelectionAvailabilityChanged(available)
                    }
                }
            }
            captionsNeedLayout = true
        }

        func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard captionsNeedLayout else { return }
            captionsNeedLayout = false
            let markers = (mapView.annotations ?? []).compactMap { mapView.view(for: $0) as? RouteMarkerView }
                .sorted { $0.routeOrder < $1.routeOrder }
            let badges = markers.map { $0.badgeFrame(in: mapView) }
            var occupied = badges
            if let button = attributionButton {
                occupied.append(button.convert(button.bounds, to: mapView))
            }
            for marker in markers {
                occupied.append(marker.placeCaption(in: mapView, avoiding: occupied))
            }
        }

        func update(_ map: MLNMapView, styleReloaded: Bool = false) {
            defer { applyCameraRequest(map) }
            if let pointSelection {
                if let coordinate = pointSelection.update(map, coordinate: parent.origin, radius: parent.selectionRadius,
                                      returnsToStart: parent.selectionReturnsToStart,
                                      bottomInset: parent.bottomInset, liveBottomInset: parent.selectionLiveBottomInset ?? parent.bottomInset,
                                      isInteracting: isInteracting || hasActiveGesture(map), animated: canAnimate) {
                    let revision = interactionRevision
                    // The panel may finish collapsing after the gesture. Commit the point under
                    // its final pin without moving the camera or publishing during updateUIView.
                    Task { @MainActor [weak self] in
                        guard let self, self.interactionRevision == revision, !self.isInteracting,
                              let map = self.mapView, !self.hasActiveGesture(map),
                              self.pointSelection?.selectedCoordinate == coordinate else { return }
                        self.parent.onSelectCoordinate?(coordinate)
                    }
                }
                return
            }
            captionsNeedLayout = true
            updateDeviceLocation(map)
            // Read the actual safe area after layout. Avoid resetting camera insets on every update.
            let insets = UIEdgeInsets(top: map.safeAreaInsets.top + Const.topInset, left: Const.sideInset,
                                     bottom: Const.sideInset, right: Const.sideInset)
            if map.contentInset != insets { map.contentInset = insets }
            guard let routeRenderer, map.style?.source(withIdentifier: RouteLineRenderer.sourceID) != nil else { return }
            let changed = renderedOrigin != parent.origin || renderedPlanID != parent.plan?.id
            if changed || styleReloaded {
                cancelReveal()
                if let annotations = map.annotations { map.removeAnnotations(annotations) }
                if let deviceAnnotation { map.addAnnotation(deviceAnnotation) }
                let start = RouteAnnotation(coordinate: parent.origin.clCoordinate, number: nil,
                                            title: Texts.Routes.yourStart)
                map.addAnnotation(start)
                var stops = [RouteAnnotation]()
                for stop in (parent.plan?.stops ?? []).sorted(by: { $0.position < $1.position }) {
                    guard let latitude = stop.store.latitude, let longitude = stop.store.longitude else { continue }
                    let point = RouteAnnotation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                                number: stop.position, title: stop.store.chainName ?? stop.store.name)
                    point.subtitle = StoreDisplayText.address(stop.store.address)
                    stops.append(point)
                }
                let points = parent.plan?.points ?? []
                let geometry = RouteRevealGeometry(points: points, stops: stops.map {
                    ShoppingCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }, marksRepeatedRoads: parent.plan?.usesRoadNetwork == true)
                routeRenderer.setRoute(geometry.canAnimate ? points : [], repeatedSections: geometry.repeatedSections)
                pendingStops = zip(stops, geometry.stopProgress).map { (annotation: $0.0, progress: $0.1) }
                if changed && geometry.canAnimate && canAnimate {
                    applyReveal(progress: .zero, animated: false)
                    revealStartedAt = CACurrentMediaTime()
                    let target = RevealTarget(owner: self)
                    let link = CADisplayLink(target: target, selector: #selector(RevealTarget.tick(_:)))
                    link.preferredFrameRateRange = CAFrameRateRange(minimum: Const.minimumFrameRate,
                                                                  maximum: Const.maximumFrameRate,
                                                                  preferred: Const.maximumFrameRate)
                    displayLink = link
                    link.add(to: .main, forMode: .common)
                } else {
                    finishReveal()
                }
                renderedPlanID = parent.plan?.id
                renderedOrigin = parent.origin
            }
            if !canAnimate && displayLink != nil { finishReveal() }
            if changed || lastSize != map.bounds.size || lastInsets != insets || lastBottomInset != parent.bottomInset {
                lastSize = map.bounds.size
                lastInsets = insets
                lastBottomInset = parent.bottomInset
                needsCameraFit = !preservesUserCamera
            }
            fitIfNeeded(map)
        }

        private var canAnimate: Bool { !parent.reduceMotion && parent.scenePhase == .active }

        private func updateDeviceLocation(_ map: MLNMapView) {
            guard let coordinate = parent.deviceCoordinate, coordinate.isValid else { return }
            if let previous = deviceAnnotation,
               previous.coordinate.latitude == coordinate.latitude,
               previous.coordinate.longitude == coordinate.longitude { return }
            if let deviceAnnotation { map.removeAnnotation(deviceAnnotation) }
            let annotation = DeviceLocationAnnotation()
            annotation.coordinate = coordinate.clCoordinate
            annotation.title = Texts.Routes.currentLocation
            deviceAnnotation = annotation
            map.addAnnotation(annotation)
        }

        private func applyCameraRequest(_ map: MLNMapView) {
            guard let request = parent.cameraRequest, request.id != lastCameraRequestID,
                  map.window != nil, map.bounds.width > .zero, map.bounds.height > .zero else { return }
            // A zoom waits for the gesture's point to be committed, including its deferred callback.
            // Location and return-to-area requests already supply an explicit replacement point.
            if isInteracting || hasActiveGesture(map) {
                switch request.action {
                case .fitRoute: return
                case .zoomIn, .zoomOut:
                    if pointSelection != nil { return }
                case .center, .fitArea: break
                }
            }
            // Keep the camera's logical center in the visible area above the sheet.
            let padding = pointSelection == nil
                ? UIEdgeInsets(top: Const.routePadding, left: Const.routePadding,
                               bottom: parent.bottomInset + Const.routePadding, right: Const.routePadding)
                : pointSelection?.cameraInsets ?? .zero
            if case .fitArea = request.action,
               map.bounds.inset(by: padding).height < Const.minimumVisibleHeight { return }
            lastCameraRequestID = request.id
            interactionRevision = UUID()
            isInteracting = false
            needsCameraFit = false
            preservesUserCamera = true
            pointSelection?.prepareCamera(map)
            let camera = map.camera
            if let coordinate = pointSelection?.selectedCoordinate { camera.centerCoordinate = coordinate.clCoordinate }
            let zoom: Double
            switch request.action {
            case .fitRoute:
                preservesUserCamera = false
                needsCameraFit = true
                fitIfNeeded(map)
                return
            case .zoomIn, .zoomOut:
                let step = request.action == .zoomIn ? Const.zoomStep : -Const.zoomStep
                zoom = min(map.maximumZoomLevel, max(map.minimumZoomLevel, (requestedZoom ?? map.zoomLevel) + step))
                requestedZoom = zoom
            case .center(let coordinate):
                guard coordinate.isValid else { return }
                camera.centerCoordinate = coordinate.clCoordinate
                zoom = min(map.maximumZoomLevel, max(Const.locationZoom, map.zoomLevel))
                requestedZoom = nil
            case .fitArea(let area):
                camera.centerCoordinate = area.center.clCoordinate
                let viewport = map.bounds.inset(by: padding)
                let diameter = max(Const.minimumVisibleHeight, min(viewport.width, viewport.height) - Const.routePadding * 2)
                let scale = Double(diameter) * map.metersPerPoint(atLatitude: area.center.latitude) / (area.radiusMeters * 2)
                zoom = min(map.maximumZoomLevel, max(map.minimumZoomLevel, map.zoomLevel + log2(scale)))
                requestedZoom = nil
            }
            camera.altitude = MLNAltitudeForZoomLevel(zoom, camera.pitch, camera.centerCoordinate.latitude, map.bounds.size)
            map.setCamera(camera, withDuration: canAnimate ? Const.cameraDuration : .zero,
                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut), edgePadding: padding) { [weak self] in
                guard self?.lastCameraRequestID == request.id else { return }
                self?.requestedZoom = nil
            }
        }

        private func hasActiveGesture(_ map: MLNMapView) -> Bool {
            (map.gestureRecognizers ?? []).contains { $0.state == .began || $0.state == .changed }
        }

        fileprivate func advanceReveal(_ link: CADisplayLink) {
            guard canAnimate, mapView?.window != nil else { finishReveal(); return }
            let elapsed = max(0, link.targetTimestamp - revealStartedAt)
            let fraction = min(1, elapsed / Const.revealDuration)
            let progress = fraction * fraction * (3 - 2 * fraction)
            applyReveal(progress: progress, animated: true)
            if fraction >= 1 { cancelReveal() }
        }

        func applyReveal(progress: Double, animated: Bool) {
            routeRenderer?.reveal(to: progress)
            let reached = pendingStops.prefix { $0.progress <= progress }
            for stop in reached {
                stop.annotation.revealedAt = animated ? CACurrentMediaTime() : nil
                mapView?.addAnnotation(stop.annotation)
            }
            pendingStops.removeFirst(reached.count)
        }

        func finishReveal() {
            applyReveal(progress: 1, animated: false)
            cancelReveal()
            for annotation in mapView?.annotations ?? [] {
                (mapView?.view(for: annotation) as? RouteMarkerView)?.finishAppearance()
            }
        }

        func cancelReveal() {
            displayLink?.invalidate()
            displayLink = nil
            pendingStops.removeAll()
        }

        private func fitIfNeeded(_ map: MLNMapView) {
            guard needsCameraFit, !preservesUserCamera, !isInteracting, !hasActiveGesture(map), map.window != nil,
                  map.bounds.width > .zero, map.bounds.height > .zero else { return }
            let availableHeight = map.bounds.height - map.contentInset.top - map.contentInset.bottom
            let bottomPadding = parent.bottomInset + Const.routePadding
            // A large sheet can cover the entire usable map. Fit once it becomes visible again.
            guard availableHeight - bottomPadding - Const.routePadding >= Const.minimumVisibleHeight else { return }
            let animated = hasFittedCamera && canAnimate
            needsCameraFit = false
            requestedZoom = nil
            hasFittedCamera = true
            var coordinates = parent.plan?.points.map(\.clCoordinate) ?? []
            coordinates.append(parent.origin.clCoordinate)
            for stop in parent.plan?.stops ?? [] {
                if let latitude = stop.store.latitude, let longitude = stop.store.longitude {
                    coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
            }
            if coordinates.count > 1 {
                map.setVisibleCoordinates(coordinates, count: UInt(coordinates.count),
                                          edgePadding: .init(top: Const.routePadding, left: Const.routePadding,
                                                             bottom: bottomPadding, right: Const.routePadding),
                                          direction: .zero, duration: animated ? Const.cameraDuration : .zero,
                                          animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut),
                                          completionHandler: nil)
            } else {
                map.setCenter(parent.origin.clCoordinate, zoomLevel: Const.initialZoom, animated: animated)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
            if annotation is DeviceLocationAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: Const.deviceMarkerID)
                    ?? MLNAnnotationView(reuseIdentifier: Const.deviceMarkerID)
                view.frame.size = CGSize(width: Const.deviceMarkerSize, height: Const.deviceMarkerSize)
                view.backgroundColor = UIColor(Color.Map.route)
                view.layer.cornerRadius = Const.deviceMarkerSize / 2
                view.layer.borderWidth = Const.deviceMarkerBorder
                view.layer.borderColor = UIColor(Color.Label.white).cgColor
                view.isAccessibilityElement = true
                view.accessibilityLabel = Texts.Routes.currentLocation
                view.accessibilityIdentifier = AccessibilityID.Routes.deviceLocation
                return view
            }
            guard let annotation = annotation as? RouteAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Const.markerID)
                ?? RouteMarkerView(reuseIdentifier: Const.markerID)
            (view as? RouteMarkerView)?.configure(annotation, animated: canAnimate)
            captionsNeedLayout = true
            return view
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: any MLNAnnotation) -> Bool { true }

        private func notifyFailure(_ failed: Bool) {
            Task { @MainActor [weak self] in self?.parent.onLoadFailure(failed) }
        }

        /// CADisplayLink retains its target; the target must not retain the map coordinator.
        private final class RevealTarget: NSObject {
            weak var owner: Coordinator?
            init(owner: Coordinator) { self.owner = owner }
            @objc func tick(_ link: CADisplayLink) {
                guard let owner else { link.invalidate(); return }
                owner.advanceReveal(link)
            }
        }
    }

    private enum Const {
        static let initialZoom = 14.0
        static let locationZoom = 15.0
        static let zoomStep = 1.0
        static let deviceMarkerID = "polka-device-location"
        static let deviceMarkerSize: CGFloat = 22
        static let deviceMarkerBorder: CGFloat = 4
        static let topInset: CGFloat = 100
        static let sideInset: CGFloat = 16
        static let routePadding: CGFloat = 36
        static let minimumVisibleHeight: CGFloat = 80
        // The demo prototype intentionally hides data credits; restore them before distribution.
        static let showsAttribution = false
        static let ornamentInset: CGFloat = 8
        static let attributionRadius: CGFloat = 4
        static let attributionHorizontalInset: CGFloat = 6
        static let attributionVerticalInset: CGFloat = 4
        static let markerID = "polka-route-stop"
        static let revealDuration = 1.6
        static let cameraDuration = 0.3
        static let minimumFrameRate: Float = 30
        static let maximumFrameRate: Float = 60
        static let userGestures: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureZoomIn,
                                                         .gestureZoomOut, .gestureOneFingerZoom]
    }
}

private final class DeviceLocationAnnotation: MLNPointAnnotation {}

private final class RouteAnnotation: MLNPointAnnotation {
    let number: Int?
    var revealedAt: CFTimeInterval?
    init(coordinate: CLLocationCoordinate2D, number: Int?, title: String) {
        self.number = number
        super.init()
        self.coordinate = coordinate
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("Use init(coordinate:number:title:)") }
}

private final class RouteMarkerView: MLNAnnotationView {
    private(set) var routeOrder = 0
    private let label = UILabel()
    private let badge = UIView()
    private let caption = UILabel()
    private let captionBackground = UIView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        badge.layer.cornerRadius = Const.size / 2
        badge.layer.borderWidth = Const.borderWidth
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontSizeToFitWidth = true
        badge.addSubview(label)
        caption.textAlignment = .center
        caption.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: Const.captionFontSize, weight: .semibold))
        caption.lineBreakMode = .byTruncatingTail
        captionBackground.addSubview(caption)
        addSubview(badge)
        addSubview(captionBackground)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("Use init(reuseIdentifier:)") }

    override func prepareForReuse() {
        super.prepareForReuse()
        finishAppearance()
    }

    func configure(_ annotation: RouteAnnotation, animated: Bool) {
        finishAppearance()
        routeOrder = annotation.number ?? 0
        label.text = annotation.number.map(String.init) ?? "A"
        label.textColor = UIColor(annotation.number == nil ? Color.Label.white : Color.Label.black)
        badge.layer.borderColor = UIColor(Color.Label.white).cgColor
        badge.backgroundColor = UIColor(annotation.number == nil ? Color.Label.black : Color.Map.route)
        caption.text = annotation.title
        caption.textColor = UIColor(Color.Label.primary)
        captionBackground.backgroundColor = UIColor(Color.Background.secondary)
        let captionSize = caption.sizeThatFits(CGSize(width: Const.maximumCaptionWidth, height: .greatestFiniteMagnitude))
        let captionWidth = min(Const.maximumCaptionWidth, captionSize.width) + Const.captionInset * 2
        let captionHeight = max(Const.captionHeight, captionSize.height + Const.captionSpacing * 2)
        let width = max(Const.size, captionWidth)
        let height = Const.size + Const.captionSpacing + captionHeight
        bounds = CGRect(x: .zero, y: .zero, width: width, height: height)
        centerOffset = CGVector(dx: .zero, dy: (height - Const.size) / 2)
        badge.frame = CGRect(x: (width - Const.size) / 2, y: .zero, width: Const.size, height: Const.size)
        label.frame = badge.bounds
        captionBackground.frame = CGRect(x: (width - captionWidth) / 2, y: Const.size + Const.captionSpacing,
                                         width: captionWidth, height: captionHeight)
        captionBackground.layer.cornerRadius = captionHeight / 2
        caption.frame = captionBackground.bounds.insetBy(dx: Const.captionInset, dy: Const.captionSpacing)
        accessibilityLabel = annotation.title
        if animated, let revealedAt = annotation.revealedAt,
           CACurrentMediaTime() - revealedAt < Const.appearanceDuration {
            alpha = .zero
            transform = CGAffineTransform(scaleX: Const.initialScale, y: Const.initialScale)
            UIView.animate(withDuration: Const.appearanceDuration, delay: .zero,
                           options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.alpha = 1
                self.transform = .identity
            }
        }
        annotation.revealedAt = nil
    }

    func finishAppearance() {
        layer.removeAllAnimations()
        alpha = 1
        transform = .identity
    }

    func badgeFrame(in map: UIView) -> CGRect { badge.convert(badge.bounds, to: map) }

    /// Prefer the design's lower caption, moving it beside the pin when stops are close together.
    func placeCaption(in map: UIView, avoiding occupied: [CGRect]) -> CGRect {
        let size = captionBackground.bounds.size
        let candidates = [
            CGPoint(x: (bounds.width - size.width) / 2, y: badge.frame.maxY + Const.captionSpacing),
            CGPoint(x: badge.frame.maxX + Const.captionSpacing, y: badge.frame.midY - size.height / 2),
            CGPoint(x: badge.frame.minX - Const.captionSpacing - size.width, y: badge.frame.midY - size.height / 2),
            CGPoint(x: (bounds.width - size.width) / 2, y: -Const.captionSpacing - size.height)
        ]
        for origin in candidates {
            let frame = CGRect(origin: origin, size: size)
            let mapFrame = convert(frame, to: map).insetBy(dx: -Const.captionClearance, dy: -Const.captionClearance)
            if map.bounds.contains(mapFrame), !occupied.contains(where: { $0.intersects(mapFrame) }) {
                captionBackground.frame = frame
                captionBackground.isHidden = false
                return mapFrame
            }
        }
        // The numbered pin and its native callout remain available at crowded zoom levels.
        captionBackground.isHidden = true
        return .null
    }

    private enum Const {
        static let size: CGFloat = 36
        static let borderWidth: CGFloat = 3
        static let appearanceDuration = 0.22
        static let initialScale: CGFloat = 0.7
        static let maximumCaptionWidth: CGFloat = 140
        static let captionHeight: CGFloat = 28
        static let captionInset: CGFloat = 8
        static let captionSpacing: CGFloat = 4
        static let captionFontSize: CGFloat = 13
        static let captionClearance: CGFloat = 2
    }
}

extension ShoppingCoordinate {
    nonisolated var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

nonisolated struct MapAttribution: Identifiable {
    let title: String
    let url: URL?
    var id: String { title + (url?.absoluteString ?? "") }

    static let openFreeMap = [
        MapAttribution(title: "OpenFreeMap", url: URL(string: "https://openfreemap.org")),
        MapAttribution(title: "© OpenMapTiles", url: URL(string: "https://www.openmaptiles.org/")),
        MapAttribution(title: "OpenStreetMap", url: URL(string: "https://www.openstreetmap.org/copyright"))
    ]
}

nonisolated struct MapAttributionContent: Identifiable {
    let id = UUID()
    let items: [MapAttribution]
}

struct MapAttributionView: View {
    @Environment(\.dismiss) private var dismiss
    let items: [MapAttribution]

    var body: some View {
        NavigationStack {
            List(items) { item in
                if let url = item.url { Link(item.title, destination: url) }
                else { Text(item.title) }
            }
            .navigationTitle(Texts.Routes.mapSources)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Texts.ShoppingList.close, role: .cancel) { dismiss() }
                }
            }
        }
    }
}
