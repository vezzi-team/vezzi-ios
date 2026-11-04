import SwiftUI

enum ShimmerStyle {
    case standard
    case lighter
}

extension EnvironmentValues {
    /// Allows a presenting screen to pause only its own placeholders beneath a sheet.
    @Entry var isShimmerEnabled = true
}

extension View {
    /// Adds a moving highlight to a loading placeholder without changing its layout.
    /// Pass the image loading state to `isActive` once an image source is available.
    func shimmer(isActive: Bool = true, style: ShimmerStyle = .standard) -> some View {
        modifier(ShimmerModifier(isActive: isActive, style: style))
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isShimmerEnabled) private var isEnabled
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
            .onScrollVisibilityChange(threshold: Const.visibilityThreshold) { isInScrollViewport = $0 }
    }

    // MARK: - Highlight

    private func shimmerOverlay(maskedBy content: Content) -> some View {
        ZStack {
            if shouldShowHighlight {
                highlight
                    .mask(content)
                    .transition(.opacity)
            }
        }
        .animation(visibilityAnimation, value: shouldShowHighlight)
    }

    private var shouldShowHighlight: Bool {
        isActive && isEnabled && isVisible && isInScrollViewport && !reduceMotion && scenePhase == .active
    }

    private var visibilityAnimation: Animation? {
        guard isVisible, !reduceMotion, scenePhase == .active else { return nil }
        return .easeInOut(duration: Const.fadeDuration)
    }

    private var highlight: some View {
        TimelineView(.animation(minimumInterval: Const.minimumFrameInterval)) { context in
            highlight(at: context.date)
                // Keep frame updates immediate without disabling the outer opacity transition.
                .transaction { $0.animation = nil }
        }
    }

    private func highlight(at date: Date) -> some View {
        // A fixed time origin keeps newly inserted and reused placeholders in phase.
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Const.duration + Const.pause)
        let progress = CGFloat(min(elapsed, Const.duration) / Const.duration)
        let leading = Const.startPosition + Const.travelDistance * progress
        let trailing = leading + Const.bandWidth

        return LinearGradient(
            gradient: highlightGradient,
            startPoint: UnitPoint(x: leading, y: leading),
            endPoint: UnitPoint(x: trailing, y: trailing)
        )
    }

    private var highlightGradient: Gradient {
        switch style {
        case .standard:
            colorScheme == .dark ? Const.darkGradient : Const.lightGradient
        case .lighter:
            colorScheme == .dark ? Const.lighterDarkGradient : Const.lighterLightGradient
        }
    }

    private enum Const {
        static let visibilityThreshold = 0.01
        static let minimumFrameInterval: TimeInterval = 1.0 / 60.0
        static let fadeDuration: TimeInterval = 0.2
        static let duration: TimeInterval = 1.3
        static let pause: TimeInterval = 0.35
        static let bandWidth: CGFloat = 1.4
        static let startPosition = -bandWidth
        static let travelDistance = bandWidth + 1
        static let lightGradient = makeGradient(opacity: 0.6)
        static let darkGradient = makeGradient(opacity: 0.12)
        static let lighterLightGradient = makeGradient(opacity: 0.85)
        static let lighterDarkGradient = makeGradient(opacity: 0.18)

        private static func makeGradient(opacity: Double) -> Gradient {
            // A rounded intensity profile softens both the edges and the central peak.
            let weights = [0.0, 0.15, 0.5, 0.85, 1.0, 0.85, 0.5, 0.15, 0.0]
            return Gradient(stops: weights.enumerated().map { index, weight in
                Gradient.Stop(
                    color: Color.Label.white.opacity(opacity * weight),
                    location: CGFloat(index) / CGFloat(weights.count - 1)
                )
            })
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
