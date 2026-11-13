import SwiftUI

struct ShoppingListPriceSummary: View {
    let total: Decimal?
    let comparison: Decimal?
    let mode: ShoppingListMode
    let isLoading: Bool
    var isCompact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var totalFontSize = Const.totalFontSize
    @ScaledMetric(relativeTo: .title2) private var compactTotalFontSize = Const.compactTotalFontSize
    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize = Const.titleFontSize
    @ScaledMetric(relativeTo: .caption) private var compactTitleFontSize = Const.compactTitleFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? Const.captionSpacing : Const.spacing) {
            title
            prices
        }
        .foregroundStyle(Color.Label.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Const.inset)
        .padding(.vertical, isCompact ? Const.compactVerticalInset : Const.inset)
        .background(Color.Background.secondary.opacity(isCompact ? 0 : 1), in: panelShape)
        .shadow(color: Color.Shadow.primary.opacity(isCompact ? 0 : Const.shadowOpacity),
                radius: Const.shadowRadius, y: Const.shadowOffset)
        .glassEffect(isCompact ? .regular : .identity, in: panelShape)
        .animation(reduceMotion ? nil : .smooth(duration: Const.collapseDuration), value: isCompact)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.summary)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: isCompact ? Const.compactCornerRadius : Const.cornerRadius)
    }

    private var title: some View {
        Text(mode == .cheaper ? Texts.ShoppingList.bestTotal : Texts.ShoppingList.fastTotal)
            .modifier(AnimatedFont(size: isCompact ? compactTitleFontSize : titleFontSize, weight: .medium))
            .contentTransition(reduceMotion ? .identity : .opacity)
    }

    private var prices: some View {
        PriceLayout(isVertical: dynamicTypeSize.isAccessibilitySize) {
            price(total, minimumScale: Const.minimumTotalPriceScale, identifier: AccessibilityID.ShoppingList.totalPrice)
                .modifier(AnimatedFont(size: isCompact ? compactTotalFontSize : totalFontSize,
                                       weight: isCompact ? .semibold : .bold))
                .lineHeight(.multiple(factor: Const.totalLineHeight / Const.totalFontSize))
            if !isCompact {
                Rectangle().fill(Color.Border.primary)
                    .transition(.opacity)
                comparisonPrice
                    .transition(.opacity)
            }
        }
    }

    private var comparisonPrice: some View {
        VStack(alignment: .leading, spacing: Const.captionSpacing) {
            Text(mode == .cheaper ? Texts.ShoppingList.fastestVariant : Texts.ShoppingList.cheapestVariant)
                .font(.caption)
                .foregroundStyle(Color.Label.secondary)
                .contentTransition(reduceMotion ? .identity : .opacity)
            price(comparison, minimumScale: Const.minimumComparisonPriceScale, identifier: AccessibilityID.ShoppingList.comparisonPrice)
                .font(.title2.weight(.semibold))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func price(_ amount: Decimal?, minimumScale: CGFloat, identifier: String) -> some View {
        let loading = isLoading && amount == nil
        let text = amount.map(formatted) ?? (loading ? formatted(Const.placeholderAmount) : "—")
        return Text(text)
            .contentTransition(reduceMotion ? .identity : .numericText(value: NSDecimalNumber(decimal: amount ?? 0).doubleValue))
            .lineLimit(1)
            .minimumScaleFactor(minimumScale)
            .opacity(loading ? 0 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: Const.placeholderRadius)
                    .fill(Color.Background.placeholder)
                    .shimmer(isActive: loading)
                    .opacity(loading ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .smooth(duration: Const.priceDuration), value: amount)
            .animation(reduceMotion ? nil : .easeInOut(duration: Const.loadingDuration), value: loading)
            .accessibilityLabel(loading ? Texts.ShoppingList.updating : text)
            .accessibilityIdentifier(identifier)
    }

    private func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "RUB").precision(.fractionLength(0...2)))
    }

    /// Animate font size without replacing the price Text or its numericText transition.
    private struct AnimatedFont: AnimatableModifier {
        var size: CGFloat
        let weight: Font.Weight

        var animatableData: CGFloat {
            get { size }
            set { size = newValue }
        }

        func body(content: Content) -> some View {
            content.font(.system(size: size, weight: weight))
        }
    }

    /// One copy of each price survives horizontal/vertical layout changes, preserving numericText.
    private struct PriceLayout: Layout {
        let isVertical: Bool

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
            guard subviews.count == Const.expandedPriceSubviewCount else {
                let total = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
                return CGSize(width: width ?? total.width, height: total.height)
            }
            let sizes = measurements(width: width, subviews: subviews)
            return CGSize(width: width ?? sizes.width, height: sizes.height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            guard subviews.count == Const.expandedPriceSubviewCount else {
                subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: nil))
                return
            }
            let sizes = measurements(width: bounds.width, subviews: subviews)
            if sizes.vertical {
                subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(sizes.total))
                subviews[1].place(at: bounds.origin, proposal: .zero)
                subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + sizes.total.height + Const.spacing),
                                  proposal: ProposedViewSize(sizes.comparison))
            } else {
                subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(sizes.total))
                let dividerX = bounds.minX + sizes.total.width + Const.spacing
                subviews[1].place(at: CGPoint(x: dividerX, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: Const.separatorWidth, height: Const.separatorHeight))
                subviews[2].place(at: CGPoint(x: dividerX + Const.separatorWidth + Const.spacing, y: bounds.midY),
                                  anchor: .leading, proposal: ProposedViewSize(sizes.comparison))
            }
        }

        private func measurements(width: CGFloat?, subviews: Subviews) -> Measurements {
            let total = subviews[0].sizeThatFits(.unspecified)
            let comparison = subviews[2].sizeThatFits(.unspecified)
            let availableTotalWidth = width.map { max(.zero, $0 - comparison.width - Const.spacing * 2 - Const.separatorWidth) }
            // Shrink the total down to its allowed scale before switching to a vertical arrangement.
            let vertical = isVertical || total.width * Const.minimumTotalPriceScale > (availableTotalWidth ?? .infinity)
            if vertical {
                let proposal = ProposedViewSize(width: width, height: nil)
                return Measurements(total: subviews[0].sizeThatFits(proposal), comparison: subviews[2].sizeThatFits(proposal), vertical: true)
            }
            let totalProposal = ProposedViewSize(width: min(total.width, availableTotalWidth ?? total.width), height: nil)
            return Measurements(total: subviews[0].sizeThatFits(totalProposal), comparison: comparison, vertical: false)
        }

        private struct Measurements {
            let total: CGSize
            let comparison: CGSize
            let vertical: Bool
            var width: CGFloat { vertical ? max(total.width, comparison.width) : total.width + comparison.width + Const.spacing * 2 + Const.separatorWidth }
            var height: CGFloat { vertical ? total.height + comparison.height + Const.spacing : max(total.height, comparison.height, Const.separatorHeight) }
        }
    }

    private enum Const {
        static let inset: CGFloat = 16
        static let spacing: CGFloat = 8
        static let captionSpacing: CGFloat = 2
        static let cornerRadius: CGFloat = 24
        static let compactCornerRadius: CGFloat = 18
        static let compactVerticalInset: CGFloat = 10
        static let titleFontSize: CGFloat = 15
        static let compactTitleFontSize: CGFloat = 12
        static let totalFontSize: CGFloat = 44
        static let compactTotalFontSize: CGFloat = 22
        static let totalLineHeight: CGFloat = 52
        static let expandedPriceSubviewCount = 3
        static let minimumTotalPriceScale: CGFloat = 0.7
        static let minimumComparisonPriceScale: CGFloat = 0.5
        static let separatorWidth: CGFloat = 1
        static let separatorHeight: CGFloat = 38
        static let placeholderRadius: CGFloat = 6
        static let placeholderAmount: Decimal = 999
        static let priceDuration: TimeInterval = 0.35
        static let loadingDuration: TimeInterval = 0.2
        static let collapseDuration: TimeInterval = 0.25
        static let shadowOpacity = 0.08
        static let shadowRadius: CGFloat = 12
        static let shadowOffset: CGFloat = 6
    }
}

#Preview("Prices — transitions and loading") {
    @Previewable @State var mode = ShoppingListMode.cheaper
    @Previewable @State var isLoading = false
    @Previewable @State var isCompact = false
    VStack {
        ShoppingListPriceSummary(total: isLoading ? nil : (mode == .cheaper ? 402 : 12422),
                                 comparison: isLoading ? nil : 12422, mode: mode, isLoading: isLoading,
                                 isCompact: isCompact)
        Picker(Texts.Search.mode, selection: $mode.animation(.smooth)) {
            Text(Texts.Search.cheaper).tag(ShoppingListMode.cheaper)
            Text(Texts.Search.faster).tag(ShoppingListMode.faster)
        }.pickerStyle(.segmented)
        Toggle(Texts.ShoppingList.updating, isOn: $isLoading)
        Toggle(isOn: $isCompact) { Text(verbatim: "Compact") }
    }
    .padding()
}

#Preview("Prices — fitting a large total") {
    ShoppingListPriceSummary(total: 123456.78, comparison: 422, mode: .cheaper, isLoading: false)
        .padding()
}

#Preview("Prices — compact") {
    ShoppingListPriceSummary(total: 402, comparison: 422, mode: .cheaper, isLoading: false, isCompact: true)
        .padding()
}

#Preview("Prices — compact, dark and large text") {
    ShoppingListPriceSummary(total: 123456.78, comparison: 422, mode: .cheaper, isLoading: false, isCompact: true)
        .padding()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
