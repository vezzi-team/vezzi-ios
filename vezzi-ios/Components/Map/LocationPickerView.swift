import SwiftUI

/// Draft route settings are applied together only after confirmation.
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: LocationPickerViewModel
    @Namespace private var guidanceNamespace
    @State private var locationRequest: UUID?
    @State private var cameraRequest: MapCameraRequest?
    @State private var mapFailed = false
    @State private var reloadRevision = 0
    @State private var attribution: MapAttributionContent?
    @State private var showsPanel = false
    @State private var detent = PresentationDetent.height(Const.initialExpandedHeight)
    @State private var visiblePanelHeight: CGFloat?
    @State private var settledPanelHeight: CGFloat?
    @State private var controlsHeight: CGFloat = Const.initialControlsHeight
    @State private var floatingHeaderHeight: CGFloat = Const.toolbarHeight
    @State private var detailsHeight: CGFloat = Const.initialDetailsHeight
    @State private var maximumPanelHeight: CGFloat = .greatestFiniteMagnitude
    @State private var showsAddressSearch = false
    private let addressSearchService: (any AddressSearching)?
    let onConfirm: (ShoppingCoordinate, ShoppingRouteOptions, String?) -> Void

    init(coordinate: ShoppingCoordinate, options: ShoppingRouteOptions, address: String? = nil, location: any DeviceLocating,
         addressResolver: (any AddressResolving)? = nil,
         addressSearchService: (any AddressSearching)? = nil,
         onConfirm: @escaping (ShoppingCoordinate, ShoppingRouteOptions, String?) -> Void) {
        _viewModel = StateObject(wrappedValue: LocationPickerViewModel(coordinate: coordinate, options: options,
                                                                     service: location, addressResolver: addressResolver, address: address))
        self.onConfirm = onConfirm
        self.addressSearchService = addressSearchService
    }

    var body: some View {
        NavigationStack {
            GeometryReader { map(in: $0) }
                .onGeometryChange(for: CGFloat.self) { floor($0.size.height * Const.maximumPanelFraction) } action: { height in
                    if height > .zero { maximumPanelHeight = height }
                }
                .navigationTitle(Texts.Routes.Settings.mapTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: close) {
                            Label { Text(Texts.Routes.back) } icon: { Image.System.chevronLeft }
                        }
                        .tint(Color.Label.primary)
                        .accessibilityIdentifier(AccessibilityID.Routes.back)
                    }
                }
        }
        .onAppear {
            detent = expandedDetent
            showsPanel = !usesFloatingPanel
        }
        .onChange(of: usesFloatingPanel) { _, floating in
            visiblePanelHeight = nil
            settledPanelHeight = nil
            showsPanel = !floating
        }
        .onChange(of: collapsedHeight) { previous, current in
            if detent == .height(previous) { detent = .height(current) }
        }
        .onChange(of: expandedHeight) { previous, current in
            if detent == .height(previous) { detent = .height(current) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { locationRequest = nil }
        }
        .task(id: locationRequest) {
            guard let request = locationRequest else { return }
            await viewModel.locate()
            guard !Task.isCancelled, locationRequest == request, viewModel.error == nil else { return }
            cameraRequest = MapCameraRequest(action: .center(viewModel.coordinate))
        }
        .task(id: addressLookupPoint) {
            guard addressLookupPoint != nil else { return }
            await viewModel.resolveAddress()
        }
        .sheet(isPresented: $showsPanel) {
            settingsPanel
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height + $0.safeAreaInsets.bottom) } action: {
                    visiblePanelHeight = $0
                }
                .onGeometryChange(for: CGFloat?.self, of: settledSheetHeight) { height in
                    if let height { settledPanelHeight = height }
                }
                .presentationDetents([collapsedDetent, expandedDetent], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.resizes)
                .presentationBackgroundInteraction(.enabled(upThrough: expandedDetent))
                .interactiveDismissDisabled()
        }
    }

    private func map(in geometry: GeometryProxy) -> some View {
        let panelHeight = obstruction(in: geometry)
        return RouteMapView(origin: viewModel.coordinate, bottomInset: cameraObstruction(in: geometry),
                            cameraRequest: cameraRequest, reloadRevision: reloadRevision,
                            selectionRadius: viewModel.options.radiusMeters,
                            selectionReturnsToStart: viewModel.options.returnToStart,
                            selectionLiveBottomInset: panelHeight,
                            selectionArea: viewModel.selectionArea,
                            onInteractionBegan: beginMapInteraction, onSelectCoordinate: viewModel.choose,
                            onSelectionAvailabilityChanged: viewModel.updateSelectionAvailability,
                            onLoadFailure: { mapFailed = $0 },
                            onShowAttribution: { attribution = MapAttributionContent(items: $0) })
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if !dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact {
                    mapGuidance
                }
            }
            .overlay {
                MapControlsView(bottomObstruction: max(.zero, panelHeight - geometry.safeAreaInsets.bottom),
                                isLocating: viewModel.isLocating,
                                zoomIn: { zoom(.zoomIn) }, zoomOut: { zoom(.zoomOut) },
                                locate: { locationRequest = UUID() })
                    .padding(.horizontal, Const.inset)
                    .padding(.top, Const.hintHeight)
                    .padding(.bottom, Const.inset)
            }
            .overlay(alignment: .bottom) {
                if usesFloatingPanel {
                    settingsPanel
                        .frame(maxWidth: Const.maximumWidth)
                        .frame(height: floatingHeight(in: geometry))
                        .clipShape(.rect(cornerRadius: Const.cornerRadius))
                        .glassEffect(.regular, in: .rect(cornerRadius: Const.cornerRadius))
                        .padding(Const.inset)
                }
            }
    }

    private var mapGuidance: some View {
        GlassEffectContainer {
            ZStack {
                if viewModel.isOutsideSelectionArea {
                    Button(action: returnToSelectionArea) { guidanceLabel(Texts.Routes.Settings.returnToArea) }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .glassEffectID(Const.returnGuidanceID, in: guidanceNamespace)
                        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                        .transition(.opacity)
                        .accessibilityIdentifier(AccessibilityID.Routes.Settings.returnToArea)
                } else {
                    guidanceLabel(Texts.Routes.Settings.moveMap)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID(Const.moveGuidanceID, in: guidanceNamespace)
                        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: Const.transitionDuration), value: viewModel.isOutsideSelectionArea)
        .padding(.horizontal, Const.inset)
        .padding(.top, Const.smallSpacing)
    }

    private func guidanceLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            .foregroundStyle(Color.Label.primary)
            .padding(.horizontal, Const.inset).padding(.vertical, Const.smallSpacing)
    }

    private var settingsPanel: some View {
        Group {
            if usesFloatingPanel {
                VStack(spacing: .zero) {
                    VStack(spacing: .zero) {
                        panelHandle
                        HStack {
                            Text(Texts.Routes.Settings.title).font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            confirmButton
                        }
                        .padding(.horizontal, Const.inset)
                        .frame(minHeight: Const.toolbarHeight)
                    }
                    .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { floatingHeaderHeight = $0 }
                    panelContent
                }
            } else {
                NavigationStack {
                    panelContent
                        .navigationTitle(Texts.Routes.Settings.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { confirmButton }
                                .sharedBackgroundVisibility(.hidden)
                        }
                }
            }
        }
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Routes.Settings.panel)
        .accessibilityAction(.escape, close)
        .sheet(item: $attribution) { MapAttributionView(items: $0.items) }
        .sheet(isPresented: $showsAddressSearch) {
            AddressSearchView(near: viewModel.coordinate, service: addressSearchService ?? MapKitAddressSearch(),
                              onSelect: chooseAddress)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var panelContent: some View {
        ScrollView {
            VStack(spacing: .zero) {
                persistentControls
                if !isMinimized { measuredDetails.transition(.opacity) }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .smooth(duration: Const.transitionDuration), value: isMinimized)
    }

    private var persistentControls: some View {
        VStack(spacing: .zero) {
            directionSection
            Button { showsAddressSearch = true } label: {
                pointRow(title: Texts.Routes.Settings.start, value: addressText, accessory: Image.System.magnifyingGlass)
            }
                .buttonStyle(.plain)
                .accessibilityHint(Texts.Routes.AddressSearch.prompt)
                .accessibilityIdentifier(AccessibilityID.Routes.Settings.coordinate)
                .padding(.horizontal, Const.inset).padding(.vertical, Const.smallSpacing)
        }
        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { controlsHeight = $0 }
    }

    private var measuredDetails: some View {
        details.onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { detailsHeight = $0 }
    }

    private var confirmButton: some View {
        Button(action: confirm) {
            Image.System.checkmark
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.Label.white)
                .padding(Const.smallSpacing)
                .frame(minWidth: Const.confirmSize, minHeight: Const.confirmSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canConfirm)
        // Keep glass outside disabled so its tint has a single animated transition.
        .glassEffect(.regular.tint(viewModel.canConfirm ? Color.accentColor : Color.Label.disable)
            .interactive(viewModel.canConfirm), in: .circle)
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.confirmTransitionDuration), value: viewModel.canConfirm)
        .accessibilityLabel(Texts.Routes.Settings.confirm)
        .accessibilityIdentifier(AccessibilityID.Routes.confirmOrigin)
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: Const.smallSpacing) {
            Button(action: expandPanel) {
                Text(Texts.Routes.Settings.direction).font(.footnote).foregroundStyle(Color.Label.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Texts.Routes.expandDetails)
            .accessibilityIdentifier(AccessibilityID.Routes.Settings.expand)
            Picker(Texts.Routes.Settings.direction, selection: $viewModel.options.returnToStart) {
                Text(Texts.Routes.Settings.roundTrip).tag(true)
                Text(Texts.Routes.Settings.oneWay).tag(false)
            }
            .pickerStyle(.segmented)
            .sensoryFeedback(.selection, trigger: viewModel.options.returnToStart)
            .accessibilityIdentifier(AccessibilityID.Routes.Settings.direction)
        }
        .padding(.horizontal, Const.inset)
        .padding(.vertical, Const.smallSpacing)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Const.inset) {
            radiusPicker
            feedback
        }
        .padding(.horizontal, Const.inset)
        .padding(.top, Const.smallSpacing)
        .padding(.bottom, Const.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addressText: String {
        viewModel.address?.addressCapitalized ?? (viewModel.isResolvingAddress ? Texts.Routes.Settings.findingAddress : Texts.Routes.Settings.selectedPoint)
    }

    private var addressLookupPoint: ShoppingCoordinate? {
        scenePhase == .active && !viewModel.isMoving ? viewModel.coordinate : nil
    }

    private func pointRow(title: String, value: String, accessory: Image? = nil,
                          valueTransition: ContentTransition = .opacity) -> some View {
        HStack(spacing: Const.smallSpacing) {
            VStack(alignment: .leading, spacing: Const.captionSpacing) {
                Text(title).font(.footnote).foregroundStyle(Color.Label.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.Label.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(valueTransition)
                    .animation(reduceMotion ? nil : .easeInOut(duration: Const.textTransitionDuration), value: value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            if let accessory {
                accessory.font(.caption.weight(.semibold)).foregroundStyle(Color.Label.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Const.rowInset)
        .background(Color.Background.elevated, in: .rect(cornerRadius: Const.rowRadius))
        .overlay { RoundedRectangle(cornerRadius: Const.rowRadius).strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth) }
    }

    private var radiusPicker: some View {
        Menu {
            Picker(Texts.Routes.Settings.radius, selection: $viewModel.options.radiusMeters) {
                Text(Texts.Routes.Settings.noLimit).tag(Int?.none)
                ForEach(LocationPickerViewModel.radiusChoices, id: \.self) { meters in
                    Text(Texts.Routes.distance(meters)).tag(Optional(meters))
                        .accessibilityIdentifier(AccessibilityID.Routes.Settings.radiusOption(meters))
                }
            }
        } label: {
            pointRow(title: Texts.Routes.Settings.radius,
                     value: viewModel.options.radiusMeters.map { Texts.Routes.distance($0) } ?? Texts.Routes.Settings.noLimit,
                     accessory: Image.System.chevronDown, valueTransition: .numericText())
        }
        .accessibilityIdentifier(AccessibilityID.Routes.Settings.radius)
    }

    @ViewBuilder private var feedback: some View {
        if viewModel.isOutsideSelectionArea,
           dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact {
            Button(Texts.Routes.Settings.returnToArea, action: returnToSelectionArea)
                .accessibilityIdentifier(AccessibilityID.Routes.Settings.returnToAreaInPanel)
        }
        if mapFailed {
            Text(Texts.Routes.mapUnavailable).font(.footnote).foregroundStyle(Color.Label.secondary)
            Button(Texts.Routes.retry) { reloadRevision += 1 }
        }
        if let error = viewModel.error {
            Text(error == .denied ? Texts.Routes.locationDenied : Texts.Routes.locationUnavailable)
                .font(.footnote).foregroundStyle(Color.Label.secondary)
            if error == .denied {
                Button(Texts.Routes.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    private var panelHandle: some View {
        Button { isMinimized ? expandPanel() : collapsePanel() } label: {
            Capsule().fill(Color.Label.tertiary)
                .frame(width: Const.handleWidth, height: Const.handleHeight)
                .frame(maxWidth: .infinity).frame(height: Const.handleTargetHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMinimized ? Texts.Routes.expandDetails : Texts.Routes.collapseDetails)
        .gesture(DragGesture(minimumDistance: Const.dragDistance).onEnded { value in
            value.translation.height > .zero ? collapsePanel() : expandPanel()
        })
    }

    private var usesFloatingPanel: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }
    private var naturalControlsHeight: CGFloat { controlsHeight + (usesFloatingPanel ? floatingHeaderHeight : Const.toolbarHeight) }
    private var collapsedHeight: CGFloat { min(naturalControlsHeight, maximumPanelHeight * Const.collapsedPanelFraction) }
    private var expandedHeight: CGFloat { min(max(naturalControlsHeight + detailsHeight, Const.initialExpandedHeight), maximumPanelHeight) }
    private var collapsedDetent: PresentationDetent { .height(collapsedHeight) }
    private var expandedDetent: PresentationDetent { .height(expandedHeight) }
    private var isMinimized: Bool { detent == collapsedDetent }

    private func floatingHeight(in geometry: GeometryProxy) -> CGFloat {
        let limit = min(max(collapsedHeight, geometry.size.height * Const.maximumPanelFraction),
                        max(.zero, geometry.size.height - Const.minimumVisibleMapHeight))
        return min(isMinimized ? collapsedHeight : expandedHeight, limit)
    }

    private func obstruction(in geometry: GeometryProxy) -> CGFloat {
        if usesFloatingPanel { return floatingHeight(in: geometry) + geometry.safeAreaInsets.bottom + Const.inset }
        return visiblePanelHeight ?? (expandedHeight + geometry.safeAreaInsets.bottom)
    }

    private func cameraObstruction(in geometry: GeometryProxy) -> CGFloat {
        if usesFloatingPanel { return obstruction(in: geometry) }
        return settledPanelHeight ?? (expandedHeight + geometry.safeAreaInsets.bottom)
    }

    private func settledSheetHeight(_ geometry: GeometryProxy) -> CGFloat? {
        let requested = isMinimized ? collapsedHeight : expandedHeight
        guard abs(geometry.size.height - requested) <= Const.layoutTolerance else { return nil }
        return ceil(geometry.size.height + geometry.safeAreaInsets.bottom)
    }

    private func beginMapInteraction() {
        locationRequest = nil
        viewModel.beginMoving()
        collapsePanel()
    }

    private func chooseAddress(_ selection: AddressSearchSelection) {
        locationRequest = nil
        viewModel.choose(selection)
    }

    private func returnToSelectionArea() {
        locationRequest = nil
        viewModel.returnToSelectionArea()
        cameraRequest = MapCameraRequest(action: .fitArea(viewModel.selectionArea))
    }

    private func zoom(_ action: MapCameraRequest.Action) {
        locationRequest = nil
        cameraRequest = MapCameraRequest(action: action)
    }

    private func collapsePanel() {
        guard !isMinimized else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: Const.transitionDuration)) { detent = collapsedDetent }
    }

    private func expandPanel() {
        withAnimation(reduceMotion ? nil : .smooth(duration: Const.transitionDuration)) {
            detent = expandedDetent
        }
    }

    private func confirm() {
        guard viewModel.canConfirm else { return }
        onConfirm(viewModel.coordinate, viewModel.options, viewModel.address)
        close()
    }

    private func close() {
        locationRequest = nil
        showsPanel = false
        dismiss()
    }

    private enum Const {
        static let moveGuidanceID = "move-map"
        static let returnGuidanceID = "return-to-area"
        static let inset: CGFloat = 16
        static let smallSpacing: CGFloat = 8
        static let captionSpacing: CGFloat = 4
        static let rowInset: CGFloat = 12
        static let rowRadius: CGFloat = 12
        static let borderWidth: CGFloat = 1
        static let cornerRadius: CGFloat = 38
        static let maximumWidth: CGFloat = 520
        static let maximumPanelFraction: CGFloat = 0.65
        static let collapsedPanelFraction: CGFloat = 0.8
        static let minimumVisibleMapHeight: CGFloat = 64
        static let toolbarHeight: CGFloat = 64
        static let initialControlsHeight: CGFloat = 160
        static let initialDetailsHeight: CGFloat = 100
        static let initialExpandedHeight: CGFloat = 280
        static let layoutTolerance: CGFloat = 1
        static let hintHeight: CGFloat = 72
        static let handleWidth: CGFloat = 36
        static let handleHeight: CGFloat = 5
        static let handleTargetHeight: CGFloat = 20
        static let dragDistance: CGFloat = 12
        static let transitionDuration = 0.25
        static let textTransitionDuration = 0.2
        static let confirmTransitionDuration = 0.2
        static let confirmSize: CGFloat = 44
    }
}

#Preview("Route settings") {
    LocationPickerView(coordinate: .previewOrigin, options: .init(returnToStart: true, radiusMeters: 500),
                       location: DeviceLocationService(), addressResolver: PreviewAddressResolver(),
                       addressSearchService: PreviewAddressSearch()) { _, _, _ in }
}
