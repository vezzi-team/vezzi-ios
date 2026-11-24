import Combine
import SwiftUI
import UIKit

enum ShimmerStyle {
    case standard
    case lighter
}

extension EnvironmentValues {
    /// Allows a presenting screen to pause only its own placeholders beneath a sheet.
    @Entry var isShimmerEnabled = true
    @Entry fileprivate var shimmerScrollActivity: ShimmerScrollActivity?
}

extension View {
    /// Adds a moving highlight to a loading placeholder without changing its layout.
    /// Pass the image loading state to `isActive` once an image source is available.
    func shimmer(isActive: Bool = true, style: ShimmerStyle = .standard) -> some View {
        modifier(ShimmerModifier(isActive: isActive, style: style))
    }

    /// Keep the placeholders static while this scroll view is moving, including during deceleration.
    func pauseShimmerWhileScrolling() -> some View {
        modifier(ScrollShimmerPause())
    }
}

private struct ScrollShimmerPause: ViewModifier {
    @Environment(\.shimmerScrollActivity) private var parent
    // Keep the same environment value throughout a gesture. Only the highlights subscribe.
    @State private var activity = ShimmerScrollActivity()

    func body(content: Content) -> some View {
        content
            .environment(\.shimmerScrollActivity, activity)
            .onReceive((parent ?? .idle).isMoving) { activity.parentIsMoving = $0 }
            .onScrollPhaseChange { _, phase in
                guard phase != .tracking else { return }
                activity.locallyMoving = phase != .idle
            }
            .onDisappear { activity.locallyMoving = false }
    }
}

private final class ShimmerScrollActivity {
    static let idle = ShimmerScrollActivity()
    let isMoving = CurrentValueSubject<Bool, Never>(false)
    var locallyMoving = false { didSet { update() } }
    var parentIsMoving = false { didSet { update() } }

    // Avoid the isolated-deinit runtime crash on iOS 26.2 when the scroll view is removed.
    nonisolated deinit {}

    private func update() {
        let moving = locallyMoving || parentIsMoving
        if moving != isMoving.value { isMoving.send(moving) }
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isShimmerEnabled) private var isEnabled
    @Environment(\.shimmerScrollActivity) private var scrollActivity
    @State private var isScrolling = false
    @State private var isVisible = false
    @State private var isInScrollViewport = true

    let isActive: Bool
    let style: ShimmerStyle

    func body(content: Content) -> some View {
        content
            .overlay {
                shimmerOverlay(maskedBy: content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .onReceive((scrollActivity ?? .idle).isMoving) { isScrolling = $0 }
            .onScrollVisibilityChange(threshold: Const.visibilityThreshold) { isInScrollViewport = $0 }
    }

    // MARK: - Highlight

    private func shimmerOverlay(maskedBy content: Content) -> some View {
        ZStack {
            if shouldShowHighlight {
                ShimmerBand(colors: highlightColors)
                    .mask(content)
                    .transition(.opacity)
            }
        }
        .animation(visibilityAnimation, value: shouldShowHighlight)
    }

    private var shouldShowHighlight: Bool {
        isActive && isEnabled && !isScrolling && isVisible && isInScrollViewport && !reduceMotion && scenePhase == .active
    }

    private var visibilityAnimation: Animation? {
        guard isVisible, !reduceMotion, scenePhase == .active else { return nil }
        return .easeInOut(duration: Const.fadeDuration)
    }

    private var highlightColors: [CGColor] {
        switch style {
        case .standard:
            colorScheme == .dark ? Const.darkGradient : Const.lightGradient
        case .lighter:
            colorScheme == .dark ? Const.lighterDarkGradient : Const.lighterLightGradient
        }
    }

    private enum Const {
        static let visibilityThreshold = 0.01
        static let fadeDuration: TimeInterval = 0.2
        static let lightGradient = makeGradient(opacity: 0.6)
        static let darkGradient = makeGradient(opacity: 0.12)
        static let lighterLightGradient = makeGradient(opacity: 0.85)
        static let lighterDarkGradient = makeGradient(opacity: 0.18)

        private static func makeGradient(opacity: CGFloat) -> [CGColor] {
            // A rounded intensity profile softens both the edges and the central peak.
            let weights: [CGFloat] = [0, 0.15, 0.5, 0.85, 1, 0.85, 0.5, 0.15, 0]
            let white = UIColor(Color.Label.white)
            return weights.map { white.withAlphaComponent(opacity * $0).cgColor }
        }
    }
}

/// The renderer moves the band without asking SwiftUI to redraw each placeholder every frame.
private struct ShimmerBand: UIViewRepresentable {
    let colors: [CGColor]

    func makeUIView(context: Context) -> BandView {
        let view = BandView()
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: BandView, context: Context) {
        view.colors = colors
    }

    final class BandView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }

        var colors: [CGColor] = [] {
            didSet {
                guard colors != oldValue, let band = layer as? CAGradientLayer else { return }
                band.colors = colors
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                layer.removeAnimation(forKey: Const.animationKey)
                return
            }

            let sweep = CAAnimationGroup()
            sweep.animations = [movement(of: "startPoint", from: -Const.bandWidth),
                                movement(of: "endPoint", from: 0)]
            sweep.duration = Const.cycle
            sweep.repeatCount = .infinity
            sweep.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            // All visible bands are at the same point in the cycle, including newly mounted cells.
            let now = CACurrentMediaTime()
            sweep.beginTime = layer.convertTime(now - now.truncatingRemainder(dividingBy: Const.cycle), from: nil)
            layer.add(sweep, forKey: Const.animationKey)
        }

        private func movement(of key: String, from start: CGFloat) -> CABasicAnimation {
            let end = start + Const.bandWidth + 1
            let movement = CABasicAnimation(keyPath: key)
            movement.fromValue = CGPoint(x: start, y: start)
            movement.toValue = CGPoint(x: end, y: end)
            movement.duration = Const.duration
            movement.timingFunction = CAMediaTimingFunction(name: .linear)
            movement.fillMode = .forwards
            movement.isRemovedOnCompletion = false
            return movement
        }

        private enum Const {
            static let duration: TimeInterval = 1.3
            static let cycle = duration + 0.35
            static let bandWidth: CGFloat = 1.4
            static let animationKey = "shimmer"
        }
    }
}

#Preview("Shimmer — light") {
    RoundedRectangle(cornerRadius: 16)
        .fill(Color.Background.placeholder)
        .frame(width: 240, height: 180)
        .shimmer()
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Shimmer — dark") {
    RoundedRectangle(cornerRadius: 16)
        .fill(Color.Background.placeholder)
        .frame(width: 240, height: 180)
        .shimmer()
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Shimmer — inactive") {
    RoundedRectangle(cornerRadius: 16)
        .fill(Color.Background.placeholder)
        .frame(width: 240, height: 180)
        .shimmer(isActive: false)
        .padding()
}

#Preview("Shimmer — lighter, light") {
    ShimmerLighterPreview()
        .preferredColorScheme(.light)
}

#Preview("Shimmer — lighter, dark") {
    ShimmerLighterPreview()
        .preferredColorScheme(.dark)
}

private struct ShimmerLighterPreview: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Const.cornerRadius)
            .fill(Color.Background.placeholder)
            .frame(width: Const.width, height: Const.height)
            .shimmer()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: Const.overlap) {
                    ForEach(0..<Const.storeCount, id: \.self) { index in
                        Circle()
                            .fill(Color.Background.placeholderLighter)
                            .frame(width: Const.storeSize, height: Const.storeSize)
                            .shimmer(style: .lighter)
                            .zIndex(-Double(index))
                    }
                }
                .padding(Const.inset)
            }
            .padding()
    }

    private enum Const {
        static let cornerRadius: CGFloat = 16
        static let width: CGFloat = 240
        static let height: CGFloat = 180
        static let storeSize: CGFloat = 24
        static let overlap: CGFloat = -4
        static let inset: CGFloat = 6
        static let storeCount = 3
    }
}

#Preview("Shimmer — loading") {
    @Previewable @State var isLoading = true
    VStack {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.Background.placeholder)
            .frame(width: 240, height: 180)
            .shimmer(isActive: isLoading)

        Toggle(isOn: $isLoading) {
            Text(verbatim: "Loading")
        }
    }
    .padding()
}

#Preview("Shimmer — reuse") {
    @Previewable @State var generation = 0
    HStack {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.Background.placeholder)
            .frame(width: 140, height: 140)
            .shimmer()

        Button { generation += 1 } label: {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.Background.placeholder)
                .frame(width: 140, height: 140)
                .shimmer()
                .id(generation)
        }
        .buttonStyle(.plain)
    }
    .padding()
}
