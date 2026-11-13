import SwiftUI

/// Shared, static feedback for empty content. The artwork stays decorative for VoiceOver.
struct MotiEmptyStateView: View {
    enum Expression { case winking, sad }

    let title: String
    let description: String
    var expression: Expression = .sad

    var body: some View {
        VStack(spacing: Const.illustrationSpacing) {
            illustration
            message
        }
        .frame(maxWidth: Const.messageWidth)
        .padding(Const.contentInset)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var illustration: some View {
        GeometryReader { geometry in
            Image.Brand.motiYarn.resizable().scaledToFit()
            face.resizable().scaledToFit()
                .frame(width: geometry.size.width * Const.faceWidth,
                       height: geometry.size.height * Const.faceHeight)
                .offset(x: geometry.size.width * Const.faceX, y: geometry.size.height * Const.faceY)
        }
        .aspectRatio(Const.illustrationAspectRatio, contentMode: .fit)
        .frame(maxWidth: Const.illustrationWidth)
        .accessibilityHidden(true)
    }

    private var face: Image {
        expression == .winking ? Image.Brand.motiWinkingFace : Image.Brand.motiSadFace
    }

    private var message: some View {
        VStack(spacing: Const.textSpacing) {
            Text(title)
                .appTextStyle(size: Const.titleSize, lineHeight: Const.titleLineHeight, weight: .bold, relativeTo: .title2)
                .foregroundStyle(Color.Label.primary)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .appTextStyle(size: Const.descriptionSize, lineHeight: Const.descriptionLineHeight, relativeTo: .body)
                .foregroundStyle(Color.Label.primary.opacity(Const.descriptionOpacity))
                .frame(maxWidth: Const.descriptionWidth)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    static var offline: Self {
        Self(title: Texts.EmptyState.offlineTitle, description: Texts.EmptyState.offlineDescription)
    }

    private enum Const {
        static let illustrationWidth: CGFloat = 224
        static let illustrationAspectRatio: CGFloat = 224 / 157.009
        // Placement of the original 200 × 150 face in the Figma mascot component.
        static let faceWidth: CGFloat = 0.267
        static let faceHeight: CGFloat = 0.2857
        static let faceX: CGFloat = 0.2937
        static let faceY: CGFloat = 0.3714
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

#Preview("Empty list") {
    MotiEmptyStateView(title: Texts.ShoppingList.emptyTitle, description: Texts.ShoppingList.emptyDescription,
                       expression: .winking)
        .frame(maxHeight: .infinity)
        .background(Color.Background.iOSPrimary)
}

#Preview("Offline — dark, large text") {
    ScrollView { MotiEmptyStateView.offline }
        .background(Color.Background.iOSPrimary)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
