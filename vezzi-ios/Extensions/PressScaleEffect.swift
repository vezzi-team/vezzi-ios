import SwiftUI
import UIKit

extension View {
    /// Scales a button or its surrounding container while its primary button is pressed.
    /// The primary button must inherit this modifier's style. Give secondary controls
    /// an explicit button style to keep their press feedback independent.
    func pressScaleEffect() -> some View {
        modifier(PressScaleModifier())
    }
}

private struct PressScaleModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(PressTrackingButtonStyle(isPressed: $isPressed))
            .scaleEffect(isPressed && !reduceMotion ? Const.pressedScale : Const.restingScale)
            .animation(pressAnimation, value: isPressed)
    }

    private var pressAnimation: Animation? {
        guard !reduceMotion, !isPressed else { return nil }
        return .smooth(duration: Const.releaseDuration)
    }

    private enum Const {
        static let pressedScale: CGFloat = 0.97
        static let restingScale: CGFloat = 1
        static let releaseDuration: TimeInterval = 0.2
    }
}

private struct PressTrackingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .gesture(TouchDownObserver { pressed in
                isPressed = pressed && isEnabled
            })
            .onDisappear { isPressed = false }
    }
}

/// Observes touches without recognizing an action or preventing the button's gestures.
private struct TouchDownObserver: UIGestureRecognizerRepresentable {
    let onPressChanged: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> TouchDownRecognizer {
        let recognizer = TouchDownRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.onPressChanged = onPressChanged
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: TouchDownRecognizer, context: Context) {
        recognizer.onPressChanged = onPressChanged
    }
}

private final class TouchDownRecognizer: UIGestureRecognizer {
    var onPressChanged: ((Bool) -> Void)?
    private var origin: CGPoint?
    private var isPressed = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard origin == nil, touches.count == 1, let touch = touches.first else {
            finish()
            return
        }
        origin = touch.location(in: nil)
        setPressed(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let origin, let touch = touches.first else { return }
        let location = touch.location(in: nil)
        if hypot(location.x - origin.x, location.y - origin.y) > Const.maximumDistance {
            finish()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish() }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { finish() }

    override func reset() {
        super.reset()
        origin = nil
        setPressed(false)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Cancel as soon as the scroll view's pan wins, without waiting for finger lift.
        preventingGestureRecognizer is UIPanGestureRecognizer
    }

    private func finish() {
        setPressed(false)
        state = .failed
    }

    private func setPressed(_ value: Bool) {
        guard isPressed != value else { return }
        isPressed = value
        onPressChanged?(value)
    }

    private enum Const {
        static let maximumDistance: CGFloat = 10
    }
}

#Preview("Press scale — scrolling") {
    PressScalePreview()
}

private struct PressScalePreview: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Const.spacing) {
                ForEach(0..<Const.cardCount, id: \.self) { _ in
                    Button {} label: {
                        Text(Texts.Home.Main.collectProducts)
                            .appTextStyle(.appText, weight: .semibold)
                            .foregroundStyle(Color.Label.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Const.cardHeight)
                            .background(Color.Background.elevated, in: .rect(cornerRadius: Const.cornerRadius))
                    }
                    .pressScaleEffect()
                }
            }
            .padding(Const.inset)
        }
        .background(Color.Background.primary)
    }

    private enum Const {
        static let spacing: CGFloat = 16
        static let cardHeight: CGFloat = 160
        static let cornerRadius: CGFloat = 16
        static let inset: CGFloat = 16
        static let cardCount = 8
    }
}
