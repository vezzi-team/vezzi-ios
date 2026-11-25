import SwiftUI

struct ProductCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var purchaseMarkSize: CGFloat = 56
    let product: Product
    var promotion: ProductPromotion? = nil
    var showsStoreBadges = true
    var showsPricePrefix = true
    /// A non-nil value turns the whole card into a purchase toggle.
    var isPurchased: Bool?
    @Binding var quantity: Int
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Const.contentSpacing) {
            productButton
                .overlay(alignment: .top) {
                    if isPurchased == nil && !dynamicTypeSize.isAccessibilitySize { artworkControls }
                }
            if isPurchased == nil && dynamicTypeSize.isAccessibilitySize { accessibleControls }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: Const.cornerRadius)
                .fill(isPurchased == true ? Color.Background.primary : Color.Background.elevated)
                .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Const.cornerRadius)
                .strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth)
                .allowsHitTesting(false)
            if let isPurchased {
                RoundedRectangle(cornerRadius: Const.cornerRadius)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isPurchased ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.purchaseTransitionDuration), value: isPurchased)
        .pressScaleEffect(acceptsRapidTaps: isPurchased != nil)
    }

    // MARK: - Product

    private var productButton: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: Const.imageSpacing) {
                artwork
                productInfo
                    .opacity(isPurchased == true ? 0.48 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .accessibilityIdentifier(AccessibilityID.Product.card(product.id))
        .accessibilityAddTraits(isPurchased == true ? .isSelected : [])
    }

    private var artwork: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: Const.cornerRadius, bottomLeadingRadius: Const.artworkCornerRadius,
                                           bottomTrailingRadius: Const.artworkCornerRadius, topTrailingRadius: Const.cornerRadius)
        return Color.Background.placeholder
            .aspectRatio(Const.artworkAspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    if geometry.size.width > 0 {
                        CatalogImage(url: product.imageURL, usage: .card(width: geometry.size.width),
                                     showsLoadingShimmer: isPurchased != true)
                            .opacity(isPurchased == true ? 0.35 : 1)
                    }
                }
            }
            .clipShape(shape)
            .overlay {
                if let isPurchased {
                    Image.System.checkmark
                        .font(.system(size: purchaseMarkSize, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.drawOff.reversed, options: .speed(Const.purchaseMarkSpeed), isActive: !reduceMotion && !isPurchased)
                        .opacity(reduceMotion && !isPurchased ? 0 : 1)
                        .allowsHitTesting(false)
                }
            }
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
            prices
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Const.contentInset)
        .padding(.bottom, Const.bottomInset)
    }

    @ViewBuilder private var prices: some View {
        if let promotion {
            let price = priceLabel(promotion.offer)
            let formatted = promotion.comparisonPrice.formatted(.currency(code: promotion.offer.currency).precision(.fractionLength(0...2)))
            let comparison = Text(formatted)
                .font(.caption)
                .strikethrough()
                .foregroundStyle(Color.Label.secondary)
                .accessibilityHidden(true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: .zero) {
                        price
                        comparison
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Const.controlsSpacing) {
                        price.layoutPriority(1)
                        comparison
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(Texts.Product.Promotion.comparison(discountTitle(promotion), formatted))
        } else {
            VStack(alignment: .leading, spacing: .zero) {
                priceLabel(product.lowestOffer)
                if dynamicTypeSize.isAccessibilitySize { textSlot("").font(.caption) }
            }
        }
    }

    private func priceLabel(_ offer: ProductOffer?) -> some View {
        Group {
            if let offer {
                ProductPriceLabel(price: offer.price, currency: offer.currency,
                                  showsPrefix: promotion == nil && showsPricePrefix, isStale: !offer.isFresh)
            } else {
                textSlot("")
            }
        }
        .appTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                      weight: .semibold, relativeTo: .headline)
    }

    private var productDescription: some View {
        VStack(alignment: .leading, spacing: Const.descriptionSpacing) {
            productName
            textSlot(product.brand.trimmingCharacters(in: .whitespacesAndNewlines))
                .appTextStyle(size: Const.brandFontSize, lineHeight: Const.brandLineHeight, relativeTo: .caption)
                .foregroundStyle(Color.Label.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            textSlot(isPurchased == nil ? product.package : [product.package, Texts.Trip.quantity(quantity)].filter { !$0.isEmpty }.joined(separator: " · "))
                .appTextStyle(size: Const.packageFontSize, lineHeight: Const.packageLineHeight,
                               relativeTo: .caption2)
                .foregroundStyle(Color.Label.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // A blank line uses the same font metrics as a populated field, including with Dynamic Type.
    private func textSlot(_ value: String) -> some View {
        Text(verbatim: value.isEmpty ? " " : value)
            .accessibilityHidden(value.isEmpty)
    }

    private var productName: some View {
        ZStack(alignment: .topLeading) {
            // Two actual lines include the interline spacing of our typography.
            Text(verbatim: "A\nA").hidden().accessibilityHidden(true)
            textSlot(product.displayName)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : Const.nameLineLimit)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: false, vertical: true)
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
        GeometryReader { geometry in
            if !stores.isEmpty {
                storeIcons(stores, fitting: geometry.size.width)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Texts.Product.offeredAtStores)
                    .accessibilityValue(stores.map(\.name).joined(separator: ", "))
            }
        }
        .frame(height: Const.storeSize)
    }

    private func storeIcons(_ stores: [ProductOffer], fitting width: CGFloat) -> some View {
        let badges = ProductStoreBadgeLayout(storeCount: stores.count, availableWidth: width)
        return HStack(spacing: ProductStoreBadgeLayout.overlap) {
            ForEach(Array(stores.prefix(badges.logoCount).enumerated()), id: \.element.storeID) { index, offer in
                StoreLogo(url: offer.logoURL, style: .lighter)
                    .frame(width: Const.storeSize, height: Const.storeSize)
                    .overlay(Circle().strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
                    .transition(reduceMotion ? .identity : .opacity)
                    .zIndex(Double(badges.logoCount - index))
            }
            if badges.extraCount > 0 {
                Text(verbatim: "+" + badges.extraCount.formatted())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.Label.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Const.storeSize, height: Const.storeSize)
                    .background(Color.Background.primary, in: .circle)
                    .overlay(Circle().strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
            }
        }
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? nil : .easeInOut(duration: Const.offerTransitionDuration),
                   value: stores.map(\.storeID))
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
        static let storeSize = ProductStoreBadgeLayout.size
        static let borderWidth: CGFloat = 1
        static let nameLineLimit = 2
        static let nameFontSize: CGFloat = 14
        static let nameLineHeight: CGFloat = 18
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
        static let purchaseTransitionDuration: TimeInterval = 0.1
        static let purchaseMarkSpeed: Double = 5
    }
}

struct ProductStoreBadgeLayout {
    static let size: CGFloat = 24
    static let overlap: CGFloat = -4
    let logoCount: Int
    let extraCount: Int

    init(storeCount: Int, availableWidth: CGFloat) {
        let slots = (0..<3).filter { Self.size + CGFloat($0) * (Self.size + Self.overlap) <= availableWidth }.count
        guard slots > 0 else {
            logoCount = 0
            extraCount = 0
            return
        }
        logoCount = storeCount <= min(2, slots) ? storeCount : slots - 1
        extraCount = storeCount - logoCount
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
