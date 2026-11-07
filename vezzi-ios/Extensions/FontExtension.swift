import SwiftUI

extension Font {
    // MARK: - App Typography

    enum AppTextStyle: String, CaseIterable {
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
}

// MARK: - Text Layout

extension View {
    /// Applies system typography with the app's metrics and Dynamic Type scaling.
    func appTextStyle(_ style: Font.AppTextStyle, weight: Font.Weight? = nil) -> some View {
        appTextStyle(size: style.size, lineHeight: style.lineHeight,
                     weight: weight ?? style.defaultWeight, relativeTo: style.textStyle)
    }

    func appTextStyle(
        size: CGFloat,
        lineHeight: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> some View {
        modifier(AppTextStyleModifier(size: size, lineHeight: lineHeight, weight: weight, textStyle: textStyle))
    }
}

private struct AppTextStyleModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat

    private let lineHeightRatio: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, lineHeight: CGFloat, weight: Font.Weight, textStyle: Font.TextStyle) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        lineHeightRatio = lineHeight / size
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: scaledSize, weight: weight))
            .lineHeight(.multiple(factor: lineHeightRatio))
    }
}

// MARK: - Preview

private struct AppTypographyPreview: View {
    @State private var isBold = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Const.spacing) {
                Toggle(isOn: $isBold) {
                    Text(verbatim: "Bold / Жирный")
                        .appTextStyle(.appText)
                }

                ForEach(Font.AppTextStyle.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: Const.labelSpacing) {
                        Text(verbatim: "\(style.rawValue) · \(Int(style.size)) / \(Int(style.lineHeight))")
                            .appTextStyle(.caption)
                            .foregroundStyle(Color.Label.secondary)
                        Text(verbatim: "Полка / Polka\nЁжик, йогурт, 123 ₽")
                            .appTextStyle(style, weight: isBold ? .bold : nil)
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

#Preview("System typography — light") {
    AppTypographyPreview()
        .preferredColorScheme(.light)
}

#Preview("System typography — dark") {
    AppTypographyPreview()
        .preferredColorScheme(.dark)
}

#Preview("System typography — accessibility") {
    AppTypographyPreview()
        .dynamicTypeSize(.accessibility3)
}

#Preview("System typography — Bold Text") {
    AppTypographyPreview()
        .environment(\.legibilityWeight, .bold)
}
