import SwiftUI

/// Keep a stable map-sized frame and pass the area covered by the bottom panel.
struct MapControlsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var buttonSize = Const.buttonSize
    @State private var zoomFeedback = false
    var bottomObstruction: CGFloat = .zero
    let isLocating: Bool
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let locate: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = max(.zero, geometry.size.height - bottomObstruction)
            let locationTop = availableHeight - controlSize
            let zoomTop = min((geometry.size.height - zoomHeight) / Const.centerDivisor,
                              locationTop - Const.spacing - zoomHeight)
            ZStack(alignment: .topTrailing) {
                if availableHeight >= controlSize {
                    if zoomTop >= .zero {
                        zoomButtons
                            .offset(y: zoomTop)
                            .transition(.opacity)
                    }
                    locationButton
                        .offset(y: locationTop)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .animation(reduceMotion ? nil : .smooth(duration: Const.movementDuration), value: bottomObstruction)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: zoomFeedback)
    }

    private var zoomButtons: some View {
        VStack(spacing: .zero) {
            Button { changeZoom(zoomIn) } label: { symbol(Image.System.plus) }
                .accessibilityLabel(Texts.Routes.zoomIn)
                .accessibilityIdentifier(AccessibilityID.Routes.zoomIn)
            Color.Border.primary.frame(height: Const.dividerHeight).padding(.horizontal, Const.dividerInset)
                .accessibilityHidden(true)
            Button { changeZoom(zoomOut) } label: { symbol(Image.System.minus) }
                .accessibilityLabel(Texts.Routes.zoomOut)
                .accessibilityIdentifier(AccessibilityID.Routes.zoomOut)
        }
        .frame(width: controlSize, height: zoomHeight)
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Const.cornerRadius))
    }

    private var locationButton: some View {
        Button(action: locate) {
            symbol(Image.System.locationFill)
                .opacity(isLocating ? .zero : 1)
                .overlay { if isLocating { ProgressView() } }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(isLocating)
        .accessibilityLabel(Texts.Routes.myLocation)
        .accessibilityValue(isLocating ? Texts.Routes.locating : "")
        .accessibilityIdentifier(AccessibilityID.Routes.locate)
    }

    private func symbol(_ image: Image) -> some View {
        image.font(.title2.weight(.semibold))
            .foregroundStyle(Color.Label.primary)
            .frame(width: controlSize, height: controlSize)
            .contentShape(.rect)
    }

    private var controlSize: CGFloat { max(buttonSize, Const.minimumTargetSize) }
    private var zoomHeight: CGFloat { controlSize * Const.zoomButtonCount + Const.dividerHeight }

    private func changeZoom(_ action: () -> Void) {
        zoomFeedback.toggle()
        action()
    }

    private enum Const {
        static let buttonSize: CGFloat = 48
        static let minimumTargetSize: CGFloat = 44
        static let zoomButtonCount: CGFloat = 2
        static let centerDivisor: CGFloat = 2
        static let spacing: CGFloat = 16
        static let cornerRadius: CGFloat = 16
        static let dividerHeight: CGFloat = 1
        static let dividerInset: CGFloat = 12
        static let movementDuration = 0.25
    }
}

#Preview("Map controls") {
    @Previewable @State var obstruction: CGFloat = 80
    VStack {
        MapControlsView(bottomObstruction: obstruction, isLocating: false, zoomIn: {}, zoomOut: {}, locate: {})
            .frame(width: 200, height: 400)
        Slider(value: $obstruction, in: 0...350)
    }
    .padding()
    .background(Color.Background.primary)
}
