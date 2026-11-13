import MapKit
import SwiftUI

/// Read-only preview of the server's route; viewing it does not start or complete a shopping plan.
struct ShoppingRouteView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: ShoppingPlan

    var body: some View {
        NavigationStack {
            List {
                Section {
                    routeMap
                        .frame(height: Const.mapHeight)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(plan.stops) { stop in ShoppingPlanStoreRow(stop: stop) }
                } header: { Text(Texts.ShoppingList.stores(plan.stops.count)) }
                Section {
                    Text(Texts.ShoppingList.addressDescription)
                    if !plan.usesRoadNetwork { Text(Texts.ShoppingList.routeApproximation) }
                }
                .font(.footnote)
                .foregroundStyle(Color.Label.secondary)
            }
            .navigationTitle(Texts.ShoppingList.routeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label { Text(Texts.ShoppingList.close) } icon: { Image.System.xmark }
                    }
                }
            }
        }
        .environment(\.isShimmerEnabled, true)
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.routePreview)
    }

    private var routeMap: some View {
        Map {
            if plan.points.count > 1 {
                MapPolyline(coordinates: plan.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.tint, lineWidth: Const.lineWidth)
            }
            Annotation(Texts.ShoppingList.start, coordinate: CLLocationCoordinate2D(
                latitude: ShoppingCoordinate.previewOrigin.latitude, longitude: ShoppingCoordinate.previewOrigin.longitude)) {
                    Image.System.walk.foregroundStyle(.tint)
                        .padding(Const.markerInset)
                        .background(Color.Background.elevated, in: .circle)
                }
            ForEach(plan.stops) { stop in
                if let latitude = stop.store.latitude, let longitude = stop.store.longitude {
                    Marker(stop.store.chainName ?? stop.store.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
            }
        }
    }

    private enum Const {
        static let mapHeight: CGFloat = 280
        static let lineWidth: CGFloat = 5
        static let markerInset: CGFloat = 8
    }
}
