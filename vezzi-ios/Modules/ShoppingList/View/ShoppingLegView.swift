import SwiftUI

/// Displays just the walk to the selected store from the server's route geometry.
struct ShoppingLegView: View {
    let trip: ShoppingTrip
    let index: Int
    let isCurrent: Bool
    let arrive: () -> Void
    @State private var presentsPanel = false
    @State private var advancing = false
    @State private var headerHeight: CGFloat = 96
    @State private var detailsHeight: CGFloat = 132
    @State private var actionHeight: CGFloat = 78
    @State private var collapsed = false
    @State private var attribution: MapAttributionContent?
    @State private var reloadRevision = 0
    @State private var mapFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var leg: ShoppingPlan?

    // The final leg of a round trip ends at the origin, after all store stops.
    private var stop: ShoppingPlanStop? { trip.plan.stops.indices.contains(index) ? trip.plan.stops[index] : nil }
    private var walkingSeconds: Int? { stop == nil ? trip.plan.returnWalkingSeconds : stop?.walkingSeconds }
    private var walkingMeters: Int? { stop == nil ? trip.plan.returnWalkingMeters : stop?.walkingMeters }
    private var previous: ShoppingPlanStop? { index > 0 ? trip.plan.stops[index - 1] : nil }

    var body: some View {
        GeometryReader { bounds in
            RouteMapView(origin: previous?.coordinate ?? trip.origin, plan: leg, previousStop: previous,
                         homeDestination: stop == nil ? trip.origin : nil, isRouteVisible: isCurrent,
                         bottomInset: min(bounds.size.height, panelHeight) + bounds.safeAreaInsets.bottom,
                         reloadRevision: reloadRevision, onInteractionBegan: { setCollapsed(true) },
                         onLoadFailure: { mapFailed = $0 },
                         onShowAttribution: { attribution = MapAttributionContent(items: $0) })
                .ignoresSafeArea()
        }
        .onChange(of: isCurrent, initial: true) { _, current in
            if current { collapsed = false }
            presentsPanel = current
        }
        .sheet(isPresented: $presentsPanel, onDismiss: {
            if advancing {
                advancing = false
                if isCurrent { arrive() }
            }
        }) {
            panel
                .presentationDetents([compactDetent, expandedDetent], selection: detent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .presentationContentInteraction(.resizes)
                .interactiveDismissDisabled()
                .sheet(item: $attribution) { MapAttributionView(items: $0.items) }
        }
        .task(id: index) {
            let route = trip.plan
            let coordinates = route.stops.compactMap(\.coordinate)
            let points = coordinates.count == route.stops.count
                ? RouteRevealGeometry.leg(points: route.points, stops: coordinates, index: index) : []
            leg = ShoppingPlan(id: route.id, total: stop?.subtotal ?? 0, savings: nil, totalSeconds: walkingSeconds ?? 0,
                               walkingMeters: walkingMeters ?? 0, stops: stop.map { [$0] } ?? [], points: points,
                               usesRoadNetwork: route.usesRoadNetwork, isSynthetic: route.isSynthetic)
        }
    }

    private var compactDetent: PresentationDetent { .height(headerHeight + actionHeight) }
    private var expandedDetent: PresentationDetent { .height(headerHeight + detailsHeight + actionHeight) }
    private var panelHeight: CGFloat { headerHeight + actionHeight + (collapsed ? 0 : detailsHeight) }

    private var detent: Binding<PresentationDetent> {
        Binding(get: { collapsed ? compactDetent : expandedDetent }, set: { selected in
            if selected == compactDetent { collapsed = true }
            else if selected == expandedDetent { collapsed = false }
        })
    }

    private func setCollapsed(_ value: Bool) {
        guard collapsed != value else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { collapsed = value }
    }

    private var panel: some View {
        ShoppingRoutePanel(isCollapsed: collapsed, headerHeight: $headerHeight, footerHeight: $actionHeight) {
            Button { setCollapsed(!collapsed) } label: { storeHeader.contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityHint(collapsed ? Texts.Routes.expandDetails : Texts.Routes.collapseDetails)
                .accessibilityIdentifier(AccessibilityID.Trip.legHeader)
                .padding(.horizontal, 10)
                .padding(.top, 32)
                .padding(.bottom, 16)
        } details: {
            panelDetails
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { detailsHeight = $0 }
        } footer: {
            ShoppingRouteButton(placement: .footer) {
                advancing = true
                presentsPanel = false
            } label: {
                Text(stop == nil ? Texts.Trip.arrivedHome : Texts.Trip.arrived)
            }
            .accessibilityIdentifier(AccessibilityID.Trip.next)
        }
        .frame(maxWidth: 600)
    }

    private var storeHeader: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if let stop {
                TripStoreLabel(stop: stop, caption: Texts.Trip.stop(index + 1, trip.plan.stops.count), large: true)
            } else {
                HStack(spacing: 12) {
                    Image.Glyph.home
                        .frame(width: 46, height: 46)
                        .background(Color.Background.placeholder, in: .rect(cornerRadius: 15))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Texts.Trip.returnHome).font(.caption).foregroundStyle(.secondary)
                        Text(Texts.Trip.home).font(.title.bold())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 4) {
                if let seconds = walkingSeconds {
                    Label { Text(Texts.ShoppingList.minutes(Int(ceil(Double(seconds) / 60)))) } icon: {
                        Image.System.walk.foregroundStyle(Color.accentColor)
                    }
                    .font(.headline)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor.opacity(0.24)) }
                }
                if let meters = walkingMeters {
                    Text(Texts.Routes.distance(meters)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .multilineTextAlignment(.leading)
    }

    private var panelDetails: some View {
        VStack(spacing: 22) {
            addresses
            if mapFailed {
                Button(Texts.Routes.retry) { reloadRevision += 1 }.accessibilityLabel(Texts.Routes.mapUnavailable)
            }
            if !trip.plan.usesRoadNetwork { Text(Texts.ShoppingList.routeApproximation).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.top, 6)
    }

    private var addresses: some View {
        HStack(spacing: 10) {
            Image.Route.legStops.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                addressRow(previous.map { Texts.Trip.fromStore($0.store.chainName ?? $0.store.name) } ?? Texts.Trip.fromStart,
                           address: previous.map { StoreDisplayText.address($0.store.address) ?? $0.store.name } ?? trip.originAddress ?? Texts.Routes.yourStart)
                if let stop {
                    addressRow(Texts.Trip.address, address: StoreDisplayText.address(stop.store.address) ?? stop.store.name)
                } else {
                    addressRow(Texts.Trip.home, address: trip.originAddress ?? Texts.Routes.yourStart)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.Background.elevated, in: .rect(cornerRadius: 19))
        .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(Color.Border.primary) }
    }

    private func addressRow(_ title: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(address.addressCapitalized).font(.callout.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
