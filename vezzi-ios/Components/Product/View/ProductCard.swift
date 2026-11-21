import SwiftUI

struct ProductCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let product: Product
    var promotion: ProductPromotion? = nil
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
            .overlay(alignment: .topLeading) {
                if let promotion { discountBadge(promotion) }
            }
            .accessibilityHidden(true)
    }

    private func discountBadge(_ promotion: ProductPromotion) -> some View {
        Text(discountTitle(promotion))
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.Label.white)
            .padding(.horizontal, Const.badgeInset)
            .frame(minWidth: Const.badgeWidth, minHeight: Const.badgeHeight, alignment: .center)
            .fixedSize()
            .background {
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular.tint(.accentColor), in: .capsule)
                    .clipShape(.capsule)
            }
            .geometryGroup()
            .rotationEffect(.degrees(Const.badgeAngle))
            .padding(.leading, Const.badgeInset)
            .padding(.top, Const.badgeTopInset)
            .allowsHitTesting(false)
    }

    private func discountTitle(_ promotion: ProductPromotion) -> String {
        let fraction = promotion.savingsFraction
        let onePercent = Decimal(1) / 100
        if fraction < onePercent { return "<" + onePercent.formatted(.percent) }
        return (-fraction).formatted(.percent.precision(.fractionLength(0)).rounded(rule: .towardZero))
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: .zero) {
            productDescription
            if let offer = promotion?.offer ?? product.lowestOffer {
                prices(for: offer)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    @ViewBuilder private func prices(for offer: ProductOffer) -> some View {
        let price = ProductPriceLabel(price: offer.price, currency: offer.currency,
                                     showsPrefix: promotion == nil && showsPricePrefix, isStale: !offer.isFresh)
            .appTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                          weight: .semibold, relativeTo: .headline)
        if let promotion {
            let formatted = promotion.comparisonPrice.formatted(.currency(code: offer.currency).precision(.fractionLength(0...2)))
            let comparison = Text(formatted)
                .font(.caption)
                .strikethrough()
                .foregroundStyle(Color.Label.secondary)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Const.controlsSpacing) {
                    price
                    comparison
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: .zero) {
                    price
                    comparison
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Texts.Product.Promotion.comparison(discountTitle(promotion), formatted))
        } else {
            price
        }
    }

    private var productDescription: some View {
        VStack(alignment: .leading, spacing: Const.descriptionSpacing) {
            productName
            brandLabel
            Text(product.package)
                .appTextStyle(size: Const.packageFontSize, lineHeight: Const.packageLineHeight,
                               relativeTo: .caption2)
                .foregroundStyle(Color.Label.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var brandLabel: some View {
        if !product.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(product.brand)
                .appTextStyle(size: Const.brandFontSize, lineHeight: Const.brandLineHeight, relativeTo: .caption)
                .foregroundStyle(Color.Label.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : Const.brandLineLimit)
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
        Text(product.displayName)
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
                artworkControlsRow
                    .padding(.horizontal, Const.artworkControlsInset)
                    .padding(.bottom, Const.artworkControlsInset)
            }
    }

    private var artworkControlsRow: some View {
        HStack(alignment: .bottom, spacing: Const.artworkControlSpacing) {
            if showsStoreBadges {
                storeBadges.padding(.bottom, Const.storeBottomInset)
            }
            quantityControl
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var accessibleControls: some View {
        VStack(alignment: .leading, spacing: Const.controlsSpacing) {
            if showsStoreBadges { storeBadges }
            quantityControl
        }
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    @ViewBuilder private var storeBadges: some View {
        let stores = product.offers.filter { $0.inStock != false }
        if !stores.isEmpty {
            GeometryReader { geometry in
                storeIcons(stores, fitting: geometry.size.width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Texts.Product.offeredAtStores)
                    .accessibilityValue(stores.map(\.name).joined(separator: ", "))
            }
            .frame(height: Const.storeSize)
        }
    }

    private func storeIcons(_ stores: [ProductOffer], fitting width: CGFloat) -> some View {
        let visible = stores.prefix(Const.maximumStoreCount).enumerated().prefix { index, _ in
            Const.storeSize + CGFloat(index) * (Const.storeSize + Const.storeOverlap) <= width
        }
        return HStack(spacing: Const.storeOverlap) {
            ForEach(Array(visible), id: \.element.storeID) { index, _ in
                StoreLogoPlaceholder(style: .lighter)
                    .frame(width: Const.storeSize, height: Const.storeSize)
                    .overlay(Circle().strokeBorder(Color.Background.elevated, lineWidth: Const.borderWidth))
                    .transition(reduceMotion ? .identity : .opacity)
                    .zIndex(-Double(index))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.offerTransitionDuration),
                   value: visible.map(\.element.storeID))
    }

    private var quantityControl: some View {
        ProductQuantityControl(productID: product.id, productName: product.name, quantity: $quantity)
            .buttonStyle(.plain)
    }

    private enum Const {
        static let badgeWidth: CGFloat = 50
        static let badgeHeight: CGFloat = 24
        static let badgeInset: CGFloat = 6
        static let badgeTopInset: CGFloat = 8
        static let badgeAngle = -6.16
        static let contentSpacing: CGFloat = 4
        static let imageSpacing: CGFloat = 10
        static let controlsSpacing: CGFloat = 8
        static let descriptionSpacing: CGFloat = 2
        static let artworkControlsInset: CGFloat = 6
        static let artworkControlSpacing: CGFloat = 16
        static let storeBottomInset: CGFloat = 5
        static let contentInset: CGFloat = 10
        static let bottomInset: CGFloat = 10
        static let cornerRadius: CGFloat = 16
        static let artworkCornerRadius: CGFloat = 10
        static let artworkAspectRatio: CGFloat = 1
        static let storeSize: CGFloat = 24
        static let storeOverlap: CGFloat = -4
        static let maximumStoreCount = 3
        static let borderWidth: CGFloat = 1
        static let nameLineLimit = 2
        static let nameFontSize: CGFloat = 14
        static let nameLineHeight: CGFloat = 18
        static let brandLineLimit = 1
        static let brandFontSize: CGFloat = 12
        static let brandLineHeight: CGFloat = 16
        static let packageFontSize: CGFloat = 11
        static let packageLineHeight: CGFloat = 13
        static let priceFontSize: CGFloat = 17
        static let priceLineHeight: CGFloat = 22
        static let shadowOpacity: Double = 0.05
        static let shadowRadius: CGFloat = 4
        static let shadowOffset: CGFloat = 2
        static let offerTransitionDuration: TimeInterval = 0.2
    }
}

struct ProductPriceLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let price: Decimal
    var currency = "RUB"
    var showsPrefix = true
    var isStale = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Const.spacing) {
            if showsPrefix { Text(Texts.Product.priceFrom).transition(.opacity) }
            priceText
        }
        .foregroundStyle(Color.Label.primary)
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: showsPrefix)
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: isStale)
        .accessibilityElement(children: .combine)
    }

    private var priceText: some View {
        HStack(alignment: .firstTextBaseline, spacing: .zero) {
            Text(price, format: .currency(code: currency).precision(.fractionLength(0...2)))
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: price)
            if isStale {
                Text(verbatim: Const.staleMarker)
                    .transition(.opacity)
                    .accessibilityLabel(Texts.Catalog.stalePrice)
            }
        }
    }

    private enum Const {
        static let spacing: CGFloat = 4
        static let staleMarker = "*"
        static let transitionDuration: TimeInterval = 0.2
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

#Preview("Product — stale price, narrow card") {
    @Previewable @State var quantity = 1
    let product: Product = {
        var product = ProductMockData.products[0]
        product.offers = product.offers.map { offer in
            var staleOffer = offer
            staleOffer.isFresh = false
            return staleOffer
        }
        return product
    }()
    ProductCard(product: product, quantity: $quantity, open: {})
        .frame(width: ProductCardPreviewConst.narrowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
}

#Preview("Product — discount") {
    @Previewable @State var quantity = 0
    let product = ProductMockData.products[0]
    if let offer = product.lowestOffer, let maximum = product.offers.map(\.price).max(),
       let promotion = ProductPromotion(offer: offer, comparisonPrice: maximum) {
        ProductCard(product: product, promotion: promotion, quantity: $quantity, open: {})
            .frame(width: ProductCardPreviewConst.narrowWidth)
            .fixedSize(horizontal: false, vertical: true)
            .padding()
    }
}

#Preview("Product — price and store transitions") {
    @Previewable @State var quantity = 1
    @Previewable @State var singleStore = false
    let product: Product = {
        var product = ProductMockData.products[0]
        if singleStore { product.offers = Array(product.offers.suffix(1)) }
        return product
    }()
    VStack {
        ProductCard(product: product, showsPricePrefix: !singleStore, quantity: $quantity, open: {})
            .frame(width: ProductCardPreviewConst.narrowWidth)
            .fixedSize(horizontal: false, vertical: true)
        Toggle(Texts.Search.faster, isOn: $singleStore)
    }
    .padding()
}

private enum ProductCardPreviewConst {
    static let narrowWidth: CGFloat = 150
}
