import SwiftUI

struct MotiMascotView: View {
    enum State: String, CaseIterable {
        case idle
        case typing
        case error
        case loading
        case success
    }

    let state: State
    var isMotionEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MotiAnimationSurface(state: state, animates: isMotionEnabled && !reduceMotion && scenePhase == .active)
            .aspectRatio(MotiFaceGeometry.canvasSize.width / MotiFaceGeometry.canvasSize.height,
                         contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct MotiAnimationSurface: UIViewRepresentable {
    let state: MotiMascotView.State
    let animates: Bool

    func makeUIView(context: Context) -> MotiAnimationView { MotiAnimationView() }

    func updateUIView(_ view: MotiAnimationView, context: Context) {
        view.update(state: state, animates: animates)
    }

    static func dismantleUIView(_ view: MotiAnimationView, coordinator: ()) {
        view.stop()
    }
}

#Preview("Moti — interactive expressions") {
    @Previewable @State var state = MotiMascotView.State.idle
    VStack {
        MotiMascotView(state: state)
        Picker("State", selection: $state) {
            ForEach(MotiMascotView.State.allCases, id: \.self) { state in
                Text(state.rawValue).tag(state)
            }
        }
        .pickerStyle(.segmented)
    }
    .padding()
    .background(Color.Background.elevated)
}
