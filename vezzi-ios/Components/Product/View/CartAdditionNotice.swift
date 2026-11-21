import SwiftUI

private nonisolated enum CartAdditionPhase: Hashable, Sendable {
    case message, checkmark
}

private enum CartAdditionMotion {
    static let appearance = Animation.smooth(duration: 0.24)
    static let morph = Animation.smooth(duration: 0.32)
    static let fade = Animation.easeOut(duration: 0.15)
}

struct CartAdditionNoticePresenter: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPresented = false
    let hasAddedProduct: Bool
    let openList: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                SceneOverlayWindow(isPresented: isPresented) { setRegion in
                    CartAdditionNotice(setRegion: setRegion, openList: openList) {
                        isPresented = false
                    }
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .onChange(of: hasAddedProduct) { _, added in
                if added { isPresented = true }
            }
            .onChange(of: scenePhase) { _, scene in
                if scene == .background { isPresented = false }
            }
    }
}

private struct CartAdditionNotice: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass
    @State private var phase: CartAdditionPhase?
    @ScaledMetric(relativeTo: .headline) private var height = Const.height
    let setRegion: (Path) -> Void
    let openList: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            if let phase {
                GlassEffectContainer {
                    noticeButton(for: phase)
                }
                .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            }
        }
        .padding(.horizontal, Const.horizontalInset)
        .padding(.top, Const.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await play() }
    }

    @ViewBuilder private func noticeButton(for phase: CartAdditionPhase) -> some View {
        switch phase {
        case .message:
            button(for: .message, identifier: AccessibilityID.Product.Quantity.additionMessage) {
                Text(Texts.Product.Quantity.addedToList)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Const.labelInset)
                    .padding(.vertical, Const.verticalInset)
                    .frame(minHeight: height)
            }
        case .checkmark:
            button(for: .checkmark, identifier: AccessibilityID.Product.Quantity.additionCheckmark) {
                Image.System.checkmark.frame(width: height, height: height)
            }
        }
    }

    private func button(for phase: CartAdditionPhase, identifier: String, @ViewBuilder label: () -> some View) -> some View {
        Button { dismiss(opensList: true) } label: {
            label().contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .font(.headline.weight(.semibold))
        .foregroundStyle(Color.Label.white)
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .capsule)
        .glassEffectID(phase, in: glass)
        .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if self.phase == phase { setRegion(Capsule().path(in: frame)) }
        }
        .accessibilityLabel(Texts.Product.Quantity.addedToList)
        .accessibilityHint(Texts.Product.Quantity.openList)
        .accessibilityIdentifier(identifier)
    }

    private func play() async {
        withAnimation(reduceMotion ? CartAdditionMotion.fade : CartAdditionMotion.appearance) { phase = .message }
        AccessibilityNotification.Announcement(Texts.Product.Quantity.addedToList).post()
        do {
            try await Task.sleep(for: Const.messageDuration)
            guard phase == .message else { return }
            withAnimation(reduceMotion ? CartAdditionMotion.fade : CartAdditionMotion.morph) { phase = .checkmark }
            try await Task.sleep(for: Const.checkmarkDuration)
            dismiss(opensList: false)
        } catch { /* Removing the window cancels playback. */ }
    }

    private func dismiss(opensList: Bool) {
        guard phase != nil else { return }
        setRegion(Path())
        if opensList { openList() }
        withAnimation(reduceMotion ? CartAdditionMotion.fade : CartAdditionMotion.appearance, completionCriteria: .removed) {
            phase = nil
        } completion: { onDismiss() }
    }

    private enum Const {
        static let height: CGFloat = 50
        static let labelInset: CGFloat = 20
        static let verticalInset: CGFloat = 12
        static let horizontalInset: CGFloat = 16
        static let topInset: CGFloat = 8
        static let messageDuration: Duration = .seconds(2)
        static let checkmarkDuration: Duration = .milliseconds(800)
    }
}

#Preview("List confirmation") {
    @Previewable @State var added = false
    Button(Texts.Product.Quantity.add) { added.toggle() }
        .modifier(CartAdditionNoticePresenter(hasAddedProduct: added, openList: {}))
}
