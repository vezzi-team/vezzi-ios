import SwiftUI

struct ProductCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let product: Product
    var showsStoreBadges = true
    var showsPricePrefix = true
    @Binding var quantity: Int
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Const.contentSpacing) {
            productButton
                .overlay(alignment: .top) {
                    if !dynamicTypeSize.isAccessibilitySize { artworkControls }
                }
            if dynamicTypeSize.isAccessibilitySize { accessibleControls }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.Background.elevated)
        .clipShape(.rect(cornerRadius: Const.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Const.cornerRadius)
            .strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
        .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
        .pressScaleEffect()
    }

    // MARK: - Product

    private var productButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Const.imageSpacing) {
                artwork
                productInfo
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityIdentifier(AccessibilityID.Product.card(product.id))
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: Const.artworkCornerRadius)
            .fill(Color.Background.placeholder)
            .aspectRatio(Const.artworkAspectRatio, contentMode: .fit)
            .shimmer()
            .accessibilityHidden(true)
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: .zero) {
            nameAndPackage
            if let offer = product.lowestOffer {
                ProductPriceLabel(price: offer.price, currency: offer.currency, showsPrefix: showsPricePrefix)
                    .appTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                                   weight: .semibold, relativeTo: .headline)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    private var nameAndPackage: some View {
        VStack(alignment: .leading, spacing: Const.namePackageSpacing) {
            productName
            Text(product.package)
                .appTextStyle(size: Const.packageFontSize, lineHeight: Const.packageLineHeight,
                               relativeTo: .caption2)
                .foregroundStyle(Color.Label.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var productName: some View {
        if dynamicTypeSize.isAccessibilitySize {
            nameLabel.fixedSize(horizontal: false, vertical: true)
        } else {
            nameLabel
                .lineLimit(Const.nameLineLimit, reservesSpace: true)
                .truncationMode(.tail)
        }
    }

    private var nameLabel: some View {
        Text(product.name)
            .appTextStyle(size: Const.nameFontSize, lineHeight: Const.nameLineHeight,
                           weight: .semibold, relativeTo: .caption)
            .foregroundStyle(Color.Label.primary)
    }

    // MARK: - Offers

    private var artworkControls: some View {
        // Match the artwork's geometry while keeping these buttons outside the product button.
        Color.clear
            .aspectRatio(Const.artworkAspectRatio, contentMode: .fit)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: Const.controlsSpacing) {
                    if showsStoreBadges {
                        storeBadges.padding(.bottom, Const.storeBottomInset)
                    }
                    Spacer(minLength: .zero)
                    quantityControl
                        .layoutPriority(1)
                }
                .padding(.horizontal, Const.artworkControlsInset)
                .padding(.bottom, Const.artworkControlsInset)
            }
    }

    private var accessibleControls: some View {
        VStack(alignment: .leading, spacing: Const.controlsSpacing) {
            if showsStoreBadges { storeBadges }
            quantityControl
        }
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    private var storeBadges: some View {
        ViewThatFits(in: .horizontal) {
            storeIcons(product.offers)
            storeIcons(Array(product.offers.prefix(Const.compactStoreCount)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Texts.Product.offeredAtStores)
        .accessibilityValue(product.offers.map(\.name).joined(separator: ", "))
    }

    private func storeIcons(_ offers: [ProductOffer]) -> some View {
        HStack(spacing: Const.storeOverlap) {
            ForEach(Array(offers.enumerated()), id: \.element.id) { index, _ in
                StoreLogoPlaceholder(style: .lighter)
                    .frame(width: Const.storeSize, height: Const.storeSize)
                    .overlay(Circle().strokeBorder(Color.Background.elevated, lineWidth: Const.borderWidth))
                    .zIndex(-Double(index))
            }
        }
    }

    private var quantityControl: some View {
        ProductQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
            .buttonStyle(.plain)
    }

    private enum Const {
        static let contentSpacing: CGFloat = 4
        static let imageSpacing: CGFloat = 10
        static let controlsSpacing: CGFloat = 8
        static let namePackageSpacing: CGFloat = 2
        static let artworkControlsInset: CGFloat = 6
        static let storeBottomInset: CGFloat = 5
        static let contentInset: CGFloat = 10
        static let bottomInset: CGFloat = 10
        static let cornerRadius: CGFloat = 16
        static let artworkCornerRadius: CGFloat = 10
        static let artworkAspectRatio: CGFloat = 1
        static let storeSize: CGFloat = 24
        static let storeOverlap: CGFloat = -4
        static let compactStoreCount = 1
        static let borderWidth: CGFloat = 1
        static let nameLineLimit = 2
        static let nameFontSize: CGFloat = 14
        static let nameLineHeight: CGFloat = 18
        static let packageFontSize: CGFloat = 11
        static let packageLineHeight: CGFloat = 13
        static let priceFontSize: CGFloat = 17
        static let priceLineHeight: CGFloat = 22
        static let shadowOpacity: Double = 0.05
        static let shadowRadius: CGFloat = 4
        static let shadowOffset: CGFloat = 2
    }
}

struct ProductPriceLabel: View {
    let price: Decimal
    var currency = "RUB"
    var showsPrefix = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Const.spacing) {
            if showsPrefix { Text(Texts.Product.priceFrom) }
            Text(price, format: .currency(code: currency).precision(.fractionLength(0...2)))
        }
        .foregroundStyle(Color.Label.primary)
        .accessibilityElement(children: .combine)
    }

    private enum Const {
        static let spacing: CGFloat = 4
    }
}

#Preview("Product labels — light") {
    @Previewable @State var milkQuantity = 1
    @Previewable @State var eggsQuantity = 0
    HStack(alignment: .top) {
        ProductCard(product: ProductMockData.products[0], quantity: $milkQuantity, open: {})
        ProductCard(product: ProductMockData.products[3], quantity: $eggsQuantity, open: {})
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Product labels — dark, accessibility") {
    @Previewable @State var quantity = 1
    ScrollView {
        ProductCard(product: ProductMockData.products[0], quantity: $quantity, open: {})
            .padding()
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
