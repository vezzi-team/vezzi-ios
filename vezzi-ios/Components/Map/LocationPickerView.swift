import SwiftUI

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: LocationPickerViewModel
    @State private var locationRequest: UUID?
    @State private var mapFailed = false
    @State private var reloadRevision = 0
    @State private var attribution: MapAttributionContent?
    @State private var controlsHeight: CGFloat = .zero
    let onConfirm: (ShoppingCoordinate) -> Void

    init(coordinate: ShoppingCoordinate, location: any DeviceLocating, onConfirm: @escaping (ShoppingCoordinate) -> Void) {
        _viewModel = StateObject(wrappedValue: LocationPickerViewModel(coordinate: coordinate, service: location))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                RouteMapView(origin: viewModel.coordinate,
                             bottomInset: controlsHeight + geometry.safeAreaInsets.bottom,
                             reloadRevision: reloadRevision, onSelectCoordinate: { coordinate in
                    locationRequest = nil
                    viewModel.choose(coordinate)
                }, onLoadFailure: { mapFailed = $0 },
                             onShowAttribution: { attribution = MapAttributionContent(items: $0) })
                    .ignoresSafeArea()
                    .safeAreaInset(edge: .bottom) {
                        ViewThatFits(in: .vertical) {
                            controls
                            ScrollView { controls }
                        }
                        .frame(maxHeight: geometry.size.height * Const.maximumPanelFraction)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { controlsHeight = $0 }
                    }
            }
                .navigationTitle(Texts.Routes.startTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Texts.ShoppingList.close, role: .cancel) { dismiss() }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { locationRequest = nil }
        }
        .task(id: locationRequest) {
            if locationRequest != nil { await viewModel.locate() }
        }
        .sheet(item: $attribution) { MapAttributionView(items: $0.items) }
    }

    private var controls: some View {
        VStack(spacing: Const.spacing) {
            Text(Texts.Routes.choosePoint).font(.headline)
            Text(Texts.Routes.coordinate(viewModel.coordinate)).font(.caption).foregroundStyle(Color.Label.secondary)
            if mapFailed {
                Text(Texts.Routes.mapUnavailable).font(.footnote)
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
            Button { locationRequest = UUID() } label: {
                HStack {
                    if viewModel.isLocating { ProgressView() } else { Image.System.location }
                    Text(Texts.Routes.myLocation)
                }.frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isLocating)
            .buttonStyle(.glass)
            .accessibilityIdentifier(AccessibilityID.Routes.locate)
            Button {
                onConfirm(viewModel.coordinate)
                dismiss()
            } label: { Text(Texts.Routes.usePoint).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier(AccessibilityID.Routes.confirmOrigin)
        }
        .controlSize(.large)
        .padding(Const.inset)
        .frame(maxWidth: Const.maximumWidth)
        .background(Color.Background.sheet, in: .rect(cornerRadius: Const.radius))
        .padding(Const.spacing)
    }

    private enum Const {
        static let spacing: CGFloat = 12
        static let inset: CGFloat = 20
        static let radius: CGFloat = 28
        static let maximumWidth: CGFloat = 520
        static let maximumPanelFraction: CGFloat = 0.65
    }
}

#Preview("Starting point") {
    LocationPickerView(coordinate: .previewOrigin, location: DeviceLocationService()) { _ in }
}
