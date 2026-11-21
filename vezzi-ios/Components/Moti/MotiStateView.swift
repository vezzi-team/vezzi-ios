import SwiftUI

/// Configurable feedback content; the caller owns scrolling and the state that drives it.
/// The static artwork stays decorative for VoiceOver and does not run an animation loop.
struct MotiStateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum Expression: Hashable { case winking, sad }

    struct Action {
        let title: String
        let perform: () -> Void
    }

    let title: String
    var description: String? = nil
    var expression: Expression = .sad
    var isLoading = false
    var action: Action? = nil

    var body: some View {
        VStack(spacing: Const.illustrationSpacing) {
            illustration
            message
            controls
        }
        .frame(maxWidth: Const.messageWidth)
        .padding(Const.contentInset)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .animation(transitionAnimation, value: title)
        .animation(transitionAnimation, value: description)
        .animation(transitionAnimation, value: action?.title)
    }

    private var illustration: some View {
        StaticMotiArtwork {
            ZStack {
                Image.Brand.motiWinkingFace.resizable().scaledToFit().opacity(expression == .winking ? 1 : 0)
                Image.Brand.motiSadFace.resizable().scaledToFit().opacity(expression == .sad ? 1 : 0)
            }
            .animation(transitionAnimation, value: expression)
        }
        .frame(maxWidth: Const.illustrationWidth)
    }

    private var message: some View {
        VStack(spacing: Const.textSpacing) {
            Text(title)
                .appTextStyle(size: Const.titleSize, lineHeight: Const.titleLineHeight, weight: .bold, relativeTo: .title2)
                .foregroundStyle(Color.Label.primary)
                .accessibilityAddTraits(.isHeader)
                .id(title)
                .transition(.opacity)
            if let description, !description.isEmpty {
                Text(description)
                    .appTextStyle(size: Const.descriptionSize, lineHeight: Const.descriptionLineHeight, relativeTo: .body)
                    .foregroundStyle(Color.Label.primary.opacity(Const.descriptionOpacity))
                    .frame(maxWidth: Const.descriptionWidth)
                    .id(description)
                    .transition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var controls: some View {
        VStack(spacing: Const.illustrationSpacing) {
            // Reserve the slot even while idle; a spinner must not move the mascot or text.
            Color.clear.frame(height: Const.spinnerHeight)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .accessibilityLabel(Texts.EmptyState.loading)
                            .transition(.opacity)
                    }
                }
                .animation(transitionAnimation, value: isLoading)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.glass)
                    .disabled(isLoading)
                    .transition(.opacity)
            }
        }
    }

    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration)
    }

    static var offline: Self {
        Self(title: Texts.EmptyState.offlineTitle, description: Texts.EmptyState.offlineDescription)
    }

    private enum Const {
        static let illustrationWidth: CGFloat = 224
        static let spinnerHeight: CGFloat = 20
        static let transitionDuration = 0.2
        static let illustrationSpacing: CGFloat = 24
        static let contentInset: CGFloat = 24
        static let messageWidth: CGFloat = 354
        static let textSpacing: CGFloat = 8
        static let titleSize: CGFloat = 24
        static let titleLineHeight: CGFloat = 29
        static let descriptionSize: CGFloat = 16
        static let descriptionLineHeight: CGFloat = 22
        static let descriptionWidth: CGFloat = 330
        static let descriptionOpacity: Double = 0.65
    }
}

/// Original bundled artwork, shared with the profile and feedback screens.
struct StaticMotiArtwork<Face: View>: View {
    @ViewBuilder var face: Face

    var body: some View {
        GeometryReader { geometry in
            Image.Brand.motiYarn.resizable().scaledToFit()
            face
                .frame(width: geometry.size.width * ArtworkMetrics.faceWidth,
                       height: geometry.size.height * ArtworkMetrics.faceHeight)
                .offset(x: geometry.size.width * ArtworkMetrics.faceX, y: geometry.size.height * ArtworkMetrics.faceY)
        }
        .aspectRatio(ArtworkMetrics.illustrationAspectRatio, contentMode: .fit)
        // Move the artwork and its face in one coordinate space during layout changes.
        .geometryGroup()
        .accessibilityHidden(true)
    }
}

private enum ArtworkMetrics {
    static let illustrationAspectRatio: CGFloat = 224 / 157.009
    // Placement of the original 200 × 150 face in the Figma mascot component.
    static let faceWidth: CGFloat = 0.267
    static let faceHeight: CGFloat = 0.2857
    static let faceX: CGFloat = 0.2937
    static let faceY: CGFloat = 0.3714
}

#Preview("Empty list") {
    MotiStateView(title: Texts.ShoppingList.emptyTitle, description: Texts.ShoppingList.emptyDescription,
                       expression: .winking)
        .frame(maxHeight: .infinity)
        .background(Color.Background.iOSPrimary)
}

#Preview("Offline — dark, large text") {
    ScrollView { MotiStateView.offline }
        .background(Color.Background.iOSPrimary)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Loading addresses") {
    MotiStateView(title: Texts.Routes.AddressSearch.loading, expression: .winking, isLoading: true)
}
