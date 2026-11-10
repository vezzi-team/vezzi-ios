import SwiftUI

struct ScrollToTopButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isVisible: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        ZStack {
            if isVisible {
                button
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: Const.transitionScale)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: isVisible)
    }

    private var button: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: Const.scrollDuration)) {
                action()
            }
        } label: {
            Label { Text(Texts.Common.scrollToTop) } icon: { Image.System.arrowUp }
                .font(.title3.weight(.semibold))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(Color.Label.primary)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private enum Const {
        static let scrollDuration: TimeInterval = 0.35
        static let transitionDuration: TimeInterval = 0.2
        static let transitionScale: CGFloat = 0.9
    }
}

#Preview("Scroll to top") {
    @Previewable @State var isVisible = true
    VStack {
        Toggle(Texts.Common.scrollToTop, isOn: $isVisible)
        ScrollToTopButton(isVisible: isVisible, accessibilityIdentifier: AccessibilityID.Search.scrollToTop) {
            isVisible = false
        }
    }
    .padding()
    .background(Color.Background.primary)
}
