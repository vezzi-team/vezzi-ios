import SwiftUI

struct HomeProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let product: HomeProduct
    @Binding var quantity: Int

    var body: some View {
        NavigationStack {
            productList
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { dismissToolbar }
                .safeAreaInset(edge: .bottom, spacing: .zero) { bottomActions }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Const.sheetCornerRadius)
    }

    // MARK: - Presentation

    private var dismissToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            dismissButton
        }
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Label { Text(Texts.Home.Product.close) } icon: { Image.System.xmark }
        }
        .tint(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Home.ProductDetail.close)
    }

    // MARK: - Product

    private var productList: some View {
        List {
            Section {
                productSummary
                offersHeading
                ForEach(product.offers) { offer in
                    offerRow(offer)
                }
            }
            .listRowInsets(EdgeInsets(top: .zero, leading: Const.contentInset,
                                      bottom: .zero, trailing: Const.contentInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .listRowSpacing(Const.rowSpacing)
        .contentMargins(.vertical, .zero, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.Background.elevated)
    }

    private var productSummary: some View {
        VStack(alignment: .leading, spacing: .zero) {
            artworkPlaceholder
                .padding(.bottom, Const.contentInset)
            productHeading
            priceSummary
                .padding(.top, Const.priceTopInset)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: Const.artworkCornerRadius)
            .fill(Color.Background.placeholder)
            .frame(height: dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
                   ? Const.compactArtworkHeight : Const.artworkHeight)
            .shimmer()
            .accessibilityHidden(true)
    }

    private var productHeading: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(product.name)
                .onestTextStyle(size: Const.titleFontSize, lineHeight: Const.titleLineHeight,
                               weight: .bold, relativeTo: .title)
                .foregroundStyle(Color.Label.primary)
                .accessibilityAddTraits(.isHeader)
            Text(product.brand + " · " + product.package)
                .onestTextStyle(size: Const.subtitleFontSize, lineHeight: Const.subtitleLineHeight, relativeTo: .subheadline)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    private var priceSummary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Const.rowSpacing) { priceLabels }
            VStack(alignment: .leading, spacing: Const.rowSpacing) { priceLabels }
        }
    }

    @ViewBuilder private var priceLabels: some View {
        if let price = product.lowestPrice {
            HomePriceLabel(price: price)
                .onestTextStyle(size: Const.sectionFontSize, lineHeight: Const.sectionLineHeight,
                               weight: .semibold, relativeTo: .title3)
        }
        Text(Texts.Home.Product.inStores(product.offers.count))
            .onestTextStyle(size: Const.storeCountFontSize, lineHeight: Const.storeCountLineHeight, relativeTo: .footnote)
            .foregroundStyle(Color.Label.secondary)
    }

    // MARK: - Stores

    private var offersHeading: some View {
        Text(Texts.Home.Product.availableNearby)
            .onestTextStyle(size: Const.sectionFontSize, lineHeight: Const.sectionLineHeight,
                           weight: .semibold, relativeTo: .title3)
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, Const.headingTopInset)
            .padding(.bottom, Const.headingBottomInset)
    }

    private func offerRow(_ offer: HomeStoreOffer) -> some View {
        HStack(spacing: Const.storeSpacing) {
            storeIcon
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Const.storeSpacing) {
                    storeSummary(offer)
                    Spacer(minLength: .zero)
                    storePrice(offer)
                }
                VStack(alignment: .leading, spacing: Const.rowSpacing) {
                    storeSummary(offer)
                    storePrice(offer)
                }
            }
        }
        .padding(.vertical, Const.rowVerticalInset)
        .accessibilityElement(children: .combine)
    }

    private var storeIcon: some View {
        Image.Home.storeIcon
            .foregroundStyle(Color.Background.placeholder)
            .frame(width: Const.storeSize, height: Const.storeSize)
            .shimmer()
            .accessibilityHidden(true)
    }

    private func storeSummary(_ offer: HomeStoreOffer) -> some View {
        VStack(alignment: .leading, spacing: Const.storeTextSpacing) {
            Text(offer.name)
                .onestTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                               weight: .semibold, relativeTo: .headline)
            Text(Texts.Search.inStock + " · " + offer.distance.formatted(
                .measurement(width: .abbreviated, usage: .asProvided).locale(locale)))
                .onestTextStyle(size: Const.availabilityFontSize, lineHeight: Const.availabilityLineHeight, relativeTo: .caption)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    private func storePrice(_ offer: HomeStoreOffer) -> some View {
        Text(offer.price, format: .currency(code: "RUB").precision(.fractionLength(0)))
            .onestTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                           weight: .semibold, relativeTo: .headline)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Bottom Action

    private var bottomActions: some View {
        VStack(spacing: Const.footerSpacing) {
            if quantity == 0 {
                addButton
            } else {
                quantityStepper
            }
            Text(quantity == 0 ? Texts.Home.Product.compareHint : Texts.Home.Product.inList)
                .onestTextStyle(size: Const.subtitleFontSize, lineHeight: Const.subtitleLineHeight, relativeTo: .subheadline)
                .foregroundStyle(Color.Label.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Const.footerHorizontalInset)
        .padding(.bottom, Const.footerBottomInset)
        .background(Color.Background.elevated)
    }

    private var addButton: some View {
        Button { quantity = 1 } label: {
            Text(Texts.Home.Quantity.add)
                .onestTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                               weight: .semibold, relativeTo: .headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .frame(minHeight: Const.actionHeight)
        .accessibilityIdentifier(AccessibilityID.Home.ProductDetail.add)
    }

    private var quantityStepper: some View {
        Stepper(value: $quantity, in: HomeViewModel.quantityRange) {
            Text(quantity, format: .number)
                .onestTextStyle(.appText, weight: .semibold)
                .monospacedDigit()
        }
        .frame(minHeight: Const.actionHeight)
        .accessibilityLabel(Texts.Home.Quantity.quantityOf(product.name))
        .accessibilityValue(Text(quantity, format: .number))
    }

    private enum Const {
        static let contentInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let priceTopInset: CGFloat = 13
        static let headingTopInset: CGFloat = 4
        static let headingBottomInset: CGFloat = 2
        static let storeSpacing: CGFloat = 12
        static let storeTextSpacing: CGFloat = 4
        static let rowVerticalInset: CGFloat = 4
        static let storeSize: CGFloat = 36
        static let artworkHeight: CGFloat = 216
        static let compactArtworkHeight: CGFloat = 40
        static let artworkCornerRadius: CGFloat = 16
        static let sheetCornerRadius: CGFloat = 34
        static let titleFontSize: CGFloat = 28
        static let titleLineHeight: CGFloat = 34
        static let subtitleFontSize: CGFloat = 15
        static let subtitleLineHeight: CGFloat = 20
        static let sectionFontSize: CGFloat = 20
        static let sectionLineHeight: CGFloat = 25
        static let storeCountFontSize: CGFloat = 13
        static let storeCountLineHeight: CGFloat = 18
        static let storeFontSize: CGFloat = 17
        static let storeLineHeight: CGFloat = 22
        static let availabilityFontSize: CGFloat = 12
        static let availabilityLineHeight: CGFloat = 16
        static let actionHeight: CGFloat = 52
        static let footerSpacing: CGFloat = 4
        static let footerHorizontalInset: CGFloat = 21
        static let footerBottomInset: CGFloat = 4
    }
}

#Preview("Product") {
    @Previewable @State var quantity = 0
    HomeProductDetailView(product: HomeMockData.products[0], quantity: $quantity)
}

#Preview("Product — dark, large text") {
    @Previewable @State var quantity = 1
    HomeProductDetailView(product: HomeMockData.products[0], quantity: $quantity)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
