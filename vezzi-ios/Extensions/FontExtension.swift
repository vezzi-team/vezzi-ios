import SwiftUI

extension Font {
    // MARK: - Onest

    /// Uses the brand style's default weight unless an explicit weight is supplied.
    /// Sizes scale with the corresponding Dynamic Type text style.
    static func onest(_ style: OnestStyle, weight: Font.Weight? = nil) -> Font {
        .custom(
            onestName(for: weight ?? style.defaultWeight),
            size: style.size,
            relativeTo: style.textStyle
        )
    }

    enum OnestStyle: String, CaseIterable {
        case title
        case subtitle
        case body
        case appText
        case caption

        fileprivate var size: CGFloat {
            switch self {
            case .title: return 48
            case .subtitle: return 32
            case .body: return 20
            case .appText: return 16
            case .caption: return 14
            }
        }

        fileprivate var lineHeight: CGFloat {
            switch self {
            case .title: return 56
            case .subtitle: return 40
            case .body: return 30
            case .appText: return 24
            case .caption: return 20
            }
        }

        fileprivate var textStyle: Font.TextStyle {
            switch self {
            case .title: return .largeTitle
            case .subtitle: return .title
            case .body, .appText: return .body
            case .caption: return .caption
            }
        }

        fileprivate var defaultWeight: Font.Weight {
            switch self {
            case .title: return .bold
            case .subtitle: return .medium
            case .body, .appText, .caption: return .regular
            }
        }
    }

    /// Named instances preserve the exact 100–900 weights of the bundled variable font.
    private static func onestName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: return "Onest-Thin"
        case .thin: return "Onest-ExtraLight"
        case .light: return "Onest-Light"
        case .regular: return "Onest-Regular"
        case .medium: return "Onest-Medium"
        case .semibold: return "Onest-SemiBold"
        case .bold: return "Onest-Bold"
        case .heavy: return "Onest-ExtraBold"
        case .black: return "Onest-Black"
        default: return "Onest-Regular"
        }
    }
}

// MARK: - Text Layout

extension View {
    /// Applies the brand font and line height, adapting to Dynamic Type and Bold Text.
    func onestTextStyle(_ style: Font.OnestStyle, weight: Font.Weight? = nil) -> some View {
        modifier(OnestTextStyleModifier(style: style, weight: weight))
    }
}

private struct OnestTextStyleModifier: ViewModifier {
    @Environment(\.legibilityWeight) private var legibilityWeight

    let style: Font.OnestStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content
            .font(.onest(style, weight: resolvedWeight))
            .lineHeight(.multiple(factor: style.lineHeight / style.size))
    }

    private var resolvedWeight: Font.Weight {
        let baseWeight = weight ?? style.defaultWeight
        guard legibilityWeight == .bold else { return baseWeight }

        switch baseWeight {
        case .ultraLight: return .light
        case .thin: return .regular
        case .light: return .medium
        case .regular: return .semibold
        case .medium, .semibold: return .bold
        case .bold: return .heavy
        case .heavy, .black: return .black
        default: return .semibold
        }
    }
}

// MARK: - Preview

private struct OnestPreview: View {
    @State private var isBold = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Const.spacing) {
                Toggle(isOn: $isBold) {
                    Text(verbatim: "Bold / Жирный")
                        .onestTextStyle(.appText)
                }

                ForEach(Font.OnestStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: Const.labelSpacing) {
                        Text(verbatim: "\(style.rawValue) · \(Int(style.size)) / \(Int(style.lineHeight))")
                            .onestTextStyle(.caption)
                            .foregroundStyle(Color.Label.secondary)
                        Text(verbatim: "Полка / Polka\nЁжик, йогурт, 123 ₽")
                            .onestTextStyle(style, weight: isBold ? .bold : nil)
                    }
                }
            }
            .padding(Const.padding)
        }
        .foregroundStyle(Color.Label.primary)
        .background(Color.Background.primary)
    }

    private enum Const {
        static let spacing: CGFloat = 24
        static let labelSpacing: CGFloat = 8
        static let padding: CGFloat = 16
    }
}

#Preview("Onest — light") {
    OnestPreview()
        .preferredColorScheme(.light)
}

#Preview("Onest — dark") {
    OnestPreview()
        .preferredColorScheme(.dark)
}

#Preview("Onest — accessibility") {
    OnestPreview()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Onest — Bold Text") {
    OnestPreview()
        .environment(\.legibilityWeight, .bold)
}
