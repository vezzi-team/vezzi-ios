import SwiftUI

/// A full-screen map with native sheet detents on iPhone and a floating panel on iPad.
struct ShoppingRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var viewModel: ShoppingRouteViewModel
    @State private var showsDetails = false
    @State private var progressPath: [ShoppingTrip.Page] = []
    @State private var pendingProgressPath: [ShoppingTrip.Page]?
    @State private var hasShownTrip = false
    @State private var showsOrigin = false
    @State private var mapFailed = false
    @State private var reloadRevision = 0
    @State private var attribution: MapAttributionContent?
    @State private var detent = PresentationDetent.large
    @State private var sheetHeight: CGFloat?
    @State private var visiblePanelHeight: CGFloat?
    @State private var routeHeaderHeight: CGFloat = Const.initialHeaderHeight
    @State private var routeActionHeight: CGFloat = Const.initialActionHeight
    @State private var headerHeight: CGFloat = Const.addressHeight + Const.addressInset
    @State private var cameraRequest: MapCameraRequest?
    @State private var locationRequest: UUID?
    @ScaledMetric(relativeTo: .largeTitle) private var durationSize = Const.durationSize
    private let location: any DeviceLocating

    init(snapshot: ShoppingRoutesSnapshot, list: ShoppingListRepository, location: any DeviceLocating) {
        _viewModel = StateObject(wrappedValue: ShoppingRouteViewModel(snapshot: snapshot, list: list, location: location))
        self.location = location
    }

    var body: some View {
        NavigationStack(path: $progressPath) {
            Group {
                if startsAtSummary, let trip = viewModel.list.trip {
                    progressPage(.summary, trip: trip)
                } else if hasShownTrip && viewModel.list.trip == nil {
                    Color.Background.primary
                } else {
                    routePreview
                }
            }
            .navigationDestination(for: ShoppingTrip.Page.self) { page in
                if let trip = viewModel.list.trip { progressPage(page, trip: trip) }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Keep a single control stationary while the navigation bar transitions between stops.
            if startsAtSummary || !progressPath.isEmpty {
                Button(action: close) {
                    Text(Texts.Trip.exit)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.trailing, 16)
                .accessibilityIdentifier(AccessibilityID.Trip.exit)
            }
        }
        .onChange(of: viewModel.list.trip?.plan.id, initial: true) { previous, id in
            if let trip = viewModel.list.trip {
                hasShownTrip = true
                if !startsAtSummary { openProgress(trip) }
            } else if previous != nil && id == nil { close() }
        }
        .onChange(of: progressPath) { _, path in
            if !startsAtSummary, let page = path.last ?? viewModel.list.trip?.pages.first {
                viewModel.list.moveTrip(to: page)
            }
        }
    }

    private var startsAtSummary: Bool { viewModel.snapshot.startsAtSummary }

    private func openProgress(_ trip: ShoppingTrip) {
        if showsDetails {
            // Push onto the existing route stack after its detent sheet has finished dismissing.
            pendingProgressPath = trip.navigationPath
            showsDetails = false
        } else {
            progressPath = trip.navigationPath
        }
    }

    private func progressPage(_ page: ShoppingTrip.Page, trip: ShoppingTrip) -> some View {
        ShoppingProgressView(trip: trip, page: page, isCurrent: progressPath.last == page, list: viewModel.list, next: { destination in
            if case .editStore = page, !progressPath.isEmpty {
                progressPath.removeLast()
            } else { progressPath.append(destination) }
        })
    }

    private var routePreview: some View {
        GeometryReader { geometry in
            map(in: geometry)
        }
        .navigationTitle(Texts.ShoppingList.routeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: close) {
                    Label { Text(Texts.Routes.back) } icon: { Image.System.chevronDown }
                }
                .foregroundStyle(Color.Label.primary)
                .tint(Color.Label.primary)
                .accessibilityIdentifier(AccessibilityID.Routes.back)
            }
        }
        .onAppear {
            expandPanel()
            showsDetails = !usesFloatingPanel && progressPath.isEmpty && pendingProgressPath == nil
                && (viewModel.list.trip == nil || hasShownTrip)
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            showsDetails = !usesFloatingPanel && progressPath.isEmpty && pendingProgressPath == nil
        }
        .onChange(of: dynamicTypeSize) { _, _ in expandPanel() }
        .onChange(of: collapsedHeight) { previous, current in
            if detent == .height(previous) { detent = .height(current) }
        }
        .onChange(of: standardHeight) { previous, current in
            if detent == .height(previous) { detent = .height(current) }
        }
        .onChange(of: showsOrigin) { _, presented in
            if presented { locationRequest = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { locationRequest = nil }
        }
        .task(id: locationRequest) {
            guard let request = locationRequest else { return }
            if let coordinate = await viewModel.locate(), !Task.isCancelled, locationRequest == request {
                cameraRequest = MapCameraRequest(action: .center(coordinate))
            }
        }
        .sheet(isPresented: $showsDetails, onDismiss: {
            if let pendingProgressPath {
                self.pendingProgressPath = nil
                progressPath = pendingProgressPath
            }
        }) {
            routePanel
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height + $0.safeAreaInsets.bottom) } action: {
                    visiblePanelHeight = $0
                }
                .onGeometryChange(for: CGFloat?.self, of: settledSheetHeight) { height in
                    if let height { sheetHeight = height }
                }
                .presentationDetents([collapsedDetent, standardDetent, .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
                .presentationBackgroundInteraction(.enabled(upThrough: standardDetent))
                .interactiveDismissDisabled()
        }
        .accessibilityIdentifier(AccessibilityID.ShoppingList.routePreview)
    }

    private func map(in geometry: GeometryProxy) -> some View {
        RouteMapView(origin: viewModel.origin, plan: viewModel.selectedPlan,
                     isRouteVisible: progressPath.isEmpty && pendingProgressPath == nil && !showsOrigin,
                     bottomInset: mapBottomInset(in: geometry),
                     cameraRequest: cameraRequest, deviceCoordinate: viewModel.deviceCoordinate,
                     reloadRevision: reloadRevision, onInteractionBegan: beginMapInteraction,
                     onLoadFailure: { mapFailed = $0 },
                     onShowAttribution: { attribution = MapAttributionContent(items: $0) })
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                mapHeader.onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { headerHeight = $0 }
            }
            .overlay { mapControls(in: geometry) }
            .overlay(alignment: .bottom) {
                if usesFloatingPanel {
                    routePanel
                        .frame(maxWidth: Const.maximumPanelWidth)
                        .frame(height: panelHeight(in: geometry))
                        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: {
                            visiblePanelHeight = $0 + geometry.safeAreaInsets.bottom + Const.inset
                        }
                        .clipShape(.rect(cornerRadius: Const.panelRadius))
                        .glassEffect(.regular, in: .rect(cornerRadius: Const.panelRadius))
                        .padding(Const.inset)
                }
            }
    }

    private func mapControls(in geometry: GeometryProxy) -> some View {
        // Only the controls follow live resizing; the map camera uses the settled panel height.
        let obstruction = (visiblePanelHeight ?? mapBottomInset(in: geometry)) - geometry.safeAreaInsets.bottom
        return MapControlsView(bottomObstruction: max(.zero, obstruction), isLocating: viewModel.isLocating,
                               zoomIn: { zoom(.zoomIn) }, zoomOut: { zoom(.zoomOut) },
                               locate: { locationRequest = UUID() })
            .padding(.top, headerHeight + Const.spacing)
            .padding(.bottom, Const.inset)
            .padding(.horizontal, Const.inset)
    }

    private func zoom(_ action: MapCameraRequest.Action) {
        locationRequest = nil
        cameraRequest = MapCameraRequest(action: action)
    }

    private var mapHeader: some View {
        VStack(spacing: Const.spacing) {
            Group {
                if viewModel.list.trip != nil {
                    originLabel(editable: false).glassEffect(.regular, in: .capsule)
                } else {
                    Button { showsOrigin = true } label: { originLabel(editable: true) }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .accessibilityIdentifier(AccessibilityID.Routes.origin)
            if mapFailed {
                VStack(spacing: Const.spacing) {
                    Text(Texts.Routes.mapUnavailable).font(.footnote)
                    Button(Texts.Routes.retry) { reloadRevision += 1 }
                }
                .padding(Const.spacing)
                .background(Color.Background.sheet, in: .rect(cornerRadius: Const.spacing))
            }
        }
        .frame(maxWidth: Const.maximumPanelWidth)
        .padding(.horizontal, Const.inset)
        .padding(.top, Const.addressInset)
    }

    private func originLabel(editable: Bool) -> some View {
        HStack(spacing: Const.addressSpacing) {
            Image.System.walk.font(.title3).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Const.addressCaptionSpacing) {
                Text(viewModel.originAddress?.addressCapitalized ?? Texts.Routes.Settings.mapTitle)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.Label.primary)
                Text(Texts.Routes.Settings.walkingMode(viewModel.routeOptions)).font(.caption).foregroundStyle(Color.Label.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if editable { Image.System.chevronRight.font(.caption.weight(.semibold)).foregroundStyle(Color.Label.secondary) }
        }
        .padding(.horizontal, Const.spacing)
        .padding(.vertical, Const.addressInset)
        .frame(minHeight: Const.addressHeight)
        .contentShape(.capsule)
    }

    private var routePanel: some View {
        ShoppingRoutePanel(isCollapsed: isMinimized, headerHeight: $routeHeaderHeight, footerHeight: $routeActionHeight) {
            routeHeader
        } details: {
            routeDetails
        } footer: {
            if let plan = viewModel.selectedPlan { startShoppingButton(plan) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Routes.panel)
        .accessibilityAction(.escape, close)
        .fullScreenCover(isPresented: $showsOrigin) {
            LocationPickerView(coordinate: viewModel.origin, options: viewModel.routeOptions,
                               address: viewModel.originAddress, location: location) { coordinate, options, address in
                viewModel.changeRoute(coordinate, options: options, address: address)
                cameraRequest = MapCameraRequest(action: .fitRoute)
            }
        }
        .sheet(item: $attribution) { MapAttributionView(items: $0.items) }
        .alert(Texts.Trip.startError, isPresented: Binding(get: { viewModel.startFailed },
                                                          set: { if !$0 { viewModel.clearStartFailure() } })) {
            Button(Texts.ShoppingList.understood, role: .cancel) {}
        }
        .alert(Texts.Routes.currentLocation, isPresented: Binding(
            get: { viewModel.locationError != nil },
            set: { if !$0 { viewModel.clearLocationError() } }
        )) {
            if viewModel.locationError == .denied {
                Button(Texts.Routes.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button(Texts.ShoppingList.close, role: .cancel) { viewModel.clearLocationError() }
        } message: {
            Text(viewModel.locationError == .denied ? Texts.Routes.locationDenied : Texts.Routes.locationUnavailable)
        }
    }

    private var routeHeader: some View {
        VStack(spacing: .zero) {
            if usesFloatingPanel { panelHandle }
            VStack(spacing: Const.spacing) {
                if let plan = viewModel.selectedPlan {
                    routeSummary(plan)
                        .accessibilityIdentifier(AccessibilityID.Routes.summary)
                } else {
                    recalculationStatus
                }
                if viewModel.availablePlans.count > 1 { routePicker }
            }
            .padding(.horizontal, Const.contentInset)
            .padding(.top, usesFloatingPanel ? .zero : Const.headerTopInset)
            .padding(.bottom, Const.contentInset)
        }
    }

    @ViewBuilder private var recalculationStatus: some View {
        if viewModel.isBusy {
            ProgressView(Texts.Routes.calculating)
                .font(.subheadline)
                .accessibilityIdentifier(AccessibilityID.Routes.recalculating)
        }
        if let message = viewModel.statusMessage {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.Label.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func routeSummary(_ plan: ShoppingPlan) -> some View {
        if isMinimized {
            Button(action: expandPanel) { summary(plan) }
                .buttonStyle(.plain)
                .accessibilityHint(Texts.Routes.expandDetails)
        } else {
            summary(plan)
        }
    }

    private var routeDetails: some View {
        ZStack(alignment: .top) {
            routeDetailsContent
                .id(viewModel.selectedPlan?.id)
                .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Const.contentInset)
        .padding(.top, Const.spacing)
        .padding(.bottom, Const.contentInset)
        .animation(routeChangeAnimation, value: viewModel.selectedPlan?.id)
    }

    private var routeDetailsContent: some View {
        VStack(spacing: Const.sectionSpacing) {
            if let plan = viewModel.selectedPlan {
                routeStops(plan)
                if !plan.usesRoadNetwork {
                    Text(Texts.ShoppingList.routeApproximation).font(.footnote).foregroundStyle(Color.Label.secondary)
                }
                if viewModel.snapshot.isSaved {
                    Text(Texts.ShoppingList.cachedCalculation).font(.footnote).foregroundStyle(Color.Label.secondary)
                }
            } else if viewModel.canRetry {
                Button(Texts.Routes.retry) { Task { await viewModel.retry() } }
                    .buttonStyle(.glass)
            }
        }
    }

    private func routeStops(_ plan: ShoppingPlan) -> some View {
        VStack(spacing: Const.spacing) {
            ForEach(plan.stops) { stop in
                RouteStopRow(stop: stop, isFirst: stop.id == plan.stops.first?.id)
            }
            if let meters = plan.returnWalkingMeters, let seconds = plan.returnWalkingSeconds {
                Label {
                    Text(Texts.Routes.Settings.returnLeg(meters: meters, seconds: seconds))
                } icon: { Image.System.location }
                    .font(.footnote).foregroundStyle(Color.Label.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func startShoppingButton(_ plan: ShoppingPlan) -> some View {
        ShoppingRouteButton(placement: .footer) {
            if let trip = viewModel.list.trip { openProgress(trip) }
            else { Task { await viewModel.start(plan.id) } }
        } label: {
            Text(viewModel.list.trip != nil ? Texts.Trip.resume : Texts.Routes.startShopping(plan.total))
                .contentTransition(reduceMotion ? .identity : .numericText(value: NSDecimalNumber(decimal: plan.total).doubleValue))
                .animation(routeChangeAnimation, value: plan.total)
        }
        .disabled(viewModel.list.trip == nil && !viewModel.canStart)
        .accessibilityIdentifier(AccessibilityID.Routes.startShopping)
    }

    private var routePicker: some View {
        Picker(Texts.Routes.options, selection: Binding(get: { viewModel.selectedID }, set: { id in
            guard id != viewModel.selectedID else { return }
            viewModel.selectedID = id
            cameraRequest = MapCameraRequest(action: .fitRoute)
        })) {
            ForEach(Array(viewModel.availablePlans.enumerated()), id: \.element.id) { index, plan in
                Text(Texts.Routes.option(index + 1)).tag(plan.id)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.Routes.options)
    }

    private func summary(_ plan: ShoppingPlan) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Const.sectionSpacing) { metrics(plan) }
            VStack(spacing: Const.addressInset) { metrics(plan) }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: plan.id)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func metrics(_ plan: ShoppingPlan) -> some View {
        Text(Texts.ShoppingList.minutes(Int(ceil(Double(plan.totalSeconds) / Const.secondsPerMinute))))
            .font(.system(size: durationSize, weight: .bold))
            .contentTransition(.numericText())
        VStack(alignment: .leading, spacing: .zero) {
            Text(Texts.Routes.walkingDistance(plan.walkingMeters))
            Text(Texts.Routes.withShopping)
        }
        .font(.caption).foregroundStyle(Color.Label.secondary)
    }

    private var panelHandle: some View {
        Button { isMinimized ? expandPanel() : collapsePanel() } label: {
            Capsule().fill(Color.Label.tertiary)
                .frame(width: Const.handleWidth, height: Const.handleHeight)
                .frame(maxWidth: .infinity).frame(height: Const.handleAreaHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMinimized ? Texts.Routes.expandDetails : Texts.Routes.collapseDetails)
        .gesture(DragGesture(minimumDistance: Const.handleDragDistance).onEnded { value in
            if value.translation.height > .zero { collapsePanel() } else { expandPanel() }
        })
    }

    private func beginMapInteraction() {
        locationRequest = nil
        collapsePanel()
    }

    private func collapsePanel() {
        guard !isMinimized else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration)) { detent = collapsedDetent }
    }

    private func expandPanel() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration)) {
            detent = dynamicTypeSize.isAccessibilitySize ? .large : standardDetent
        }
    }

    private func close() {
        locationRequest = nil
        showsDetails = false
        dismiss()
    }

    private var usesFloatingPanel: Bool { horizontalSizeClass == .regular }
    private var routeChangeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration)
    }
    private var collapsedHeight: CGFloat {
        max(Const.minimumCollapsedHeight, routeHeaderHeight + (viewModel.selectedPlan == nil ? .zero : routeActionHeight))
    }
    private var collapsedDetent: PresentationDetent { .height(collapsedHeight) }
    private var standardDetent: PresentationDetent { .height(standardHeight) }
    private var isMinimized: Bool { detent == collapsedDetent }
    private var standardHeight: CGFloat {
        let stops = min(Const.maximumStores, viewModel.snapshot.plans.map { $0.stops.count }.max() ?? .zero)
        return max(Const.panelBaseHeight + CGFloat(stops) * Const.stopHeight,
                   collapsedHeight + Const.minimumDetailsHeight)
    }

    private func panelHeight(in geometry: GeometryProxy) -> CGFloat {
        let requested = isMinimized ? collapsedHeight : standardHeight
        return usesFloatingPanel ? min(requested, geometry.size.height * Const.maximumMapInset) : requested
    }

    private func mapBottomInset(in geometry: GeometryProxy) -> CGFloat {
        if usesFloatingPanel {
            return panelHeight(in: geometry) + geometry.safeAreaInsets.bottom + Const.inset
        }
        if detent == .large { return geometry.size.height + geometry.safeAreaInsets.bottom }
        return sheetHeight ?? (panelHeight(in: geometry) + geometry.safeAreaInsets.bottom)
    }

    private func settledSheetHeight(_ geometry: GeometryProxy) -> CGFloat? {
        let requested = isMinimized ? collapsedHeight : standardHeight
        // Interactive resizing reports every intermediate height. Fit only the settled detent.
        guard detent != .large, abs(geometry.size.height - requested) <= Const.layoutTolerance else { return nil }
        return ceil(geometry.size.height + geometry.safeAreaInsets.bottom)
    }

    private enum Const {
        static let initialHeaderHeight: CGFloat = 120
        static let initialActionHeight: CGFloat = 64
        static let minimumCollapsedHeight: CGFloat = 80
        static let minimumDetailsHeight: CGFloat = 140
        static let panelBaseHeight: CGFloat = 216
        static let stopHeight: CGFloat = 70
        static let maximumStores = 3
        static let durationSize: CGFloat = 31
        static let maximumPanelWidth: CGFloat = 600
        static let panelRadius: CGFloat = 38
        static let maximumMapInset: CGFloat = 0.65
        static let inset: CGFloat = 20
        static let contentInset: CGFloat = 16
        static let addressInset: CGFloat = 8
        static let addressSpacing: CGFloat = 10
        static let addressCaptionSpacing: CGFloat = 1
        static let addressHeight: CGFloat = 52
        static let spacing: CGFloat = 12
        static let headerTopInset: CGFloat = 20
        static let sectionSpacing: CGFloat = 20
        static let transitionDuration = 0.25
        static let secondsPerMinute = 60.0
        static let handleWidth: CGFloat = 36
        static let handleHeight: CGFloat = 5
        static let handleAreaHeight: CGFloat = 24
        static let handleDragDistance: CGFloat = 12
        static let layoutTolerance: CGFloat = 1
    }
}

private struct RouteStopRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var badgeSize = Const.badgeSize
    let stop: ShoppingPlanStop
    let isFirst: Bool

    var body: some View {
        HStack(spacing: Const.spacing) {
            Text(stop.position, format: .number).font(.headline.bold())
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.Background.secondary, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Const.captionSpacing) {
                Text(stop.store.chainName ?? stop.store.name).font(.headline)
                if let seconds = stop.walkingSeconds, let meters = stop.walkingMeters {
                    Text(Texts.Routes.leg(seconds: seconds, meters: meters, isFirst: isFirst))
                        .font(.caption).foregroundStyle(Color.Label.secondary)
                }
                Text(Texts.ShoppingList.products(stop.items.count))
                    .font(.caption).foregroundStyle(Color.Label.secondary)
                if dynamicTypeSize.isAccessibilitySize { price }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { price }
        }
        .frame(maxWidth: .infinity, minHeight: Const.minimumHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var price: some View {
        Text(stop.subtotal, format: .currency(code: "RUB").precision(.fractionLength(0...2)))
            .font(.callout.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
    }

    private enum Const {
        static let badgeSize: CGFloat = 32
        static let spacing: CGFloat = 12
        static let captionSpacing: CGFloat = 2
        static let minimumHeight: CGFloat = 58
    }
}

#Preview("Route options") {
    @Previewable @StateObject var list = ShoppingListPreview.repository()
    if let plans = list.planResult?.plans, let first = plans.first,
       let snapshot = ShoppingRoutesSnapshot(plans: plans, selectedID: first.id, origin: list.origin, isSaved: false) {
        ShoppingRouteView(snapshot: snapshot, list: list, location: DeviceLocationService())
    } else {
        ProgressView().task {
            list.setAccount(ShoppingListPreview.account)
            list.setPresented(true)
            await list.refresh()
        }
    }
}
