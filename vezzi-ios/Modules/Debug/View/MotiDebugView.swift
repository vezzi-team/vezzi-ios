import SwiftUI

struct MotiDebugView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var state = MotiMascotView.State.idle
    @State private var withoutMotion = false
    @State private var isRunningTransitions = false

    var body: some View {
        VStack(spacing: .zero) {
            preview
            Form {
                emotionsSection
                playbackSection
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.Background.primary)
        .onestTextStyle(.appText)
        .foregroundStyle(Color.Label.primary)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AccessibilityID.Debug.Moti.screen)
        .task(id: isRunningTransitions) {
            await runTransitions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                isRunningTransitions = false
            }
        }
        .onDisappear {
            isRunningTransitions = false
        }
    }

    // MARK: - Sections

    private var preview: some View {
        VStack(spacing: Const.previewSpacing) {
            MotiMascotView(state: state, isMotionEnabled: !withoutMotion)
                .frame(maxWidth: Const.mascotWidth)
                .frame(maxWidth: .infinity)
            Text(title(for: state))
                .onestTextStyle(.caption)
                .foregroundStyle(Color.Label.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(Texts.Debug.Moti.state)
                .accessibilityValue(title(for: state))
                .accessibilityIdentifier(AccessibilityID.Debug.Moti.currentState)
        }
        .padding(.horizontal, Const.previewInset)
        .padding(.vertical, Const.previewSpacing)
    }

    private var emotionsSection: some View {
        Section(Texts.Debug.Moti.emotions) {
            ForEach(MotiMascotView.State.allCases, id: \.self) { emotion in
                emotionButton(emotion)
            }
        }
        .listRowBackground(Color.Background.elevated)
    }

    private var playbackSection: some View {
        Section {
            Toggle(Texts.Debug.Moti.noMotion, isOn: $withoutMotion)
                .accessibilityIdentifier(AccessibilityID.Debug.Moti.noMotion)
            Button(isRunningTransitions ? Texts.Debug.Moti.stop : Texts.Debug.Moti.rapidTransitions) {
                isRunningTransitions.toggle()
            }
            .accessibilityIdentifier(AccessibilityID.Debug.Moti.rapidTransitions)
        } header: {
            Text(Texts.Debug.Moti.playback)
        } footer: {
            Text(Texts.Debug.Moti.playbackHint)
                .onestTextStyle(.caption)
        }
        .listRowBackground(Color.Background.elevated)
    }

    private func emotionButton(_ emotion: MotiMascotView.State) -> some View {
        Button {
            isRunningTransitions = false
            state = emotion
        } label: {
            HStack {
                Text(title(for: emotion))
                    .foregroundStyle(Color.Label.primary)
                Spacer()
                if state == emotion {
                    Image.System.checkmark
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(state == emotion ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.Debug.Moti.state(emotion.rawValue))
    }

    // MARK: - Playback

    private func runTransitions() async {
        guard isRunningTransitions else { return }
        for emotion in Const.transitionSequence {
            guard isRunningTransitions, !Task.isCancelled, scenePhase == .active else { return }
            state = emotion
            do {
                try await Task.sleep(for: Const.transitionInterval)
            } catch {
                return
            }
        }
        isRunningTransitions = false
    }

    private func title(for emotion: MotiMascotView.State) -> String {
        switch emotion {
        case .idle: return Texts.Debug.Moti.idle
        case .typing: return Texts.Debug.Moti.typing
        case .error: return Texts.Debug.Moti.error
        case .loading: return Texts.Debug.Moti.loading
        case .success: return Texts.Debug.Moti.success
        }
    }

    private enum Const {
        static let mascotWidth: CGFloat = 240
        static let previewSpacing: CGFloat = 8
        static let previewInset: CGFloat = 20
        static let transitionInterval: Duration = .milliseconds(120)
        static let transitionSequence: [MotiMascotView.State] = [
            .typing, .error, .loading, .success, .idle, .error, .typing, .loading, .idle,
        ]
    }
}

#Preview("Moti debug") {
    NavigationStack {
        MotiDebugView()
            .navigationTitle(Texts.Debug.Moti.title)
    }
}

#Preview("Moti debug — dark, large text") {
    NavigationStack {
        MotiDebugView()
            .navigationTitle(Texts.Debug.Moti.title)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
