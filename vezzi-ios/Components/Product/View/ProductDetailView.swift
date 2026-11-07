import SwiftUI

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    let product: Product
    let relatedProducts: [Product]
    let selection: ProductSelection
    var showsPricePrefix = true

    var body: some View {
        NavigationStack(path: $path) {
            productPage(for: product)
                .toolbar { dismissToolbar }
                .navigationDestination(for: String.self) { productID in
                    if let product = ([product] + relatedProducts).first(where: { $0.id == productID }) {
                        productPage(for: product)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Const.sheetCornerRadius)
    }

    // MARK: - Navigation

    private func productPage(for product: Product) -> some View {
        ProductDetailPage(product: product, relatedProducts: [self.product] + relatedProducts,
                          selection: selection, showsPricePrefix: showsPricePrefix) { alternative in
            path.append(alternative.id)
        }
    }

    private var dismissToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            dismissButton
        }
    }

    private var dismissButton: some View {
        Button { dismiss() } label: {
            Label { Text(Texts.Product.close) } icon: { Image.System.xmark }
        }
        .tint(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Product.Detail.close)
    }

    private enum Const {
        static let sheetCornerRadius: CGFloat = 34
    }
}

private struct ProductDetailPage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let product: Product
    let relatedProducts: [Product]
    @ObservedObject var selection: ProductSelection
    let showsPricePrefix: Bool
    let selectProduct: (Product) -> Void

    var body: some View {
        productList
            .navigationTitle(product.name)
            .navigationSubtitle(product.brand + " · " + product.package)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaBar(edge: .bottom, spacing: .zero) { bottomActions }
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
                if !alternatives.isEmpty {
                    sectionHeading(Texts.Product.alternatives)
                        .padding(.top, Const.sectionSpacing - Const.rowSpacing)
                    alternativeProducts
                        .padding(.bottom, Const.contentInset)
                }
            }
            .listRowInsets(EdgeInsets(top: .zero, leading: Const.contentInset,
                                      bottom: .zero, trailing: Const.contentInset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, .zero)
        .listRowSpacing(Const.rowSpacing)
        .contentMargins(.vertical, .zero, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.Background.elevated)
    }

    private var productSummary: some View {
        VStack(alignment: .leading, spacing: .zero) {
            artworkPlaceholder
                .padding(.bottom, Const.contentInset)
            priceSummary
        }
        .padding(.top, Const.rowSpacing)
        .padding(.bottom, Const.sectionSpacing - Const.rowSpacing)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: Const.artworkCornerRadius)
            .fill(Color.Background.placeholder)
            .frame(height: dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
                   ? Const.compactArtworkHeight : Const.artworkHeight)
            .shimmer()
            .accessibilityHidden(true)
    }

    private var priceSummary: some View {
        VStack(alignment: .leading, spacing: .zero) {
            if let offer = product.lowestOffer {
                ProductPriceLabel(price: offer.price, currency: offer.currency, showsPrefix: showsPricePrefix)
                    .appTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                                   weight: .bold, relativeTo: .title)
            }
            Text(Texts.Product.inStores(product.offers.count))
                .appTextStyle(size: Const.subtitleFontSize, lineHeight: Const.subtitleLineHeight, relativeTo: .subheadline)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    // MARK: - Stores

    private var offersHeading: some View {
        sectionHeading(Texts.Product.availableNearby)
            .padding(.bottom, Const.headingBottomInset)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .appTextStyle(size: Const.sectionFontSize, lineHeight: Const.sectionLineHeight,
                           weight: .semibold, relativeTo: .title3)
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private func offerRow(_ offer: ProductOffer) -> some View {
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
        .frame(minHeight: Const.storeRowHeight)
        .accessibilityElement(children: .combine)
    }

    private var storeIcon: some View {
        StoreLogoPlaceholder()
            .frame(width: Const.storeSize, height: Const.storeSize)
    }

    private func storeSummary(_ offer: ProductOffer) -> some View {
        VStack(alignment: .leading, spacing: Const.storeTextSpacing) {
            Text(offer.name)
                .appTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                               weight: .semibold, relativeTo: .headline)
            Text(offerSubtitle(offer))
                .appTextStyle(size: Const.availabilityFontSize, lineHeight: Const.availabilityLineHeight, relativeTo: .caption)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    private func offerSubtitle(_ offer: ProductOffer) -> String {
        let availability = offer.inStock.map { $0 ? Texts.Product.inStock : Texts.Product.outOfStock }
        let distance = offer.distance?.formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
        return [availability, distance].compactMap { $0 }.joined(separator: " · ")
    }

    private func storePrice(_ offer: ProductOffer) -> some View {
        Text(offer.price, format: .currency(code: offer.currency).precision(.fractionLength(0...2)))
            .appTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                           weight: .semibold, relativeTo: .headline)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Alternatives

    private var alternatives: [Product] {
        relatedProducts.filter { $0.id != product.id }
    }

    private var alternativeProducts: some View {
        LazyVGrid(columns: alternativeColumns, alignment: .leading, spacing: Const.contentInset) {
            ForEach(alternatives) { alternative in
                ProductCard(product: alternative, showsPricePrefix: showsPricePrefix, quantity: quantityBinding(for: alternative.id)) {
                    selectProduct(alternative)
                }
            }
        }
    }

    private var alternativeColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: Const.minimumCardWidth), spacing: Const.contentInset, alignment: .top)]
    }

    // MARK: - Bottom Action

    private var bottomActions: some View {
        ProductActions(productName: product.name, quantity: quantityBinding(for: product.id))
            .padding(.horizontal, Const.footerHorizontalInset)
            .padding(.top, Const.rowSpacing)
            .padding(.bottom, Const.footerBottomInset)
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { selection.quantity(for: productID) },
            set: { selection.setQuantity($0, for: productID) }
        )
    }

    private enum Const {
        static let contentInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let sectionSpacing: CGFloat = 30
        static let headingBottomInset: CGFloat = 2
        static let storeSpacing: CGFloat = 12
        static let storeTextSpacing: CGFloat = 4
        static let rowVerticalInset: CGFloat = 4
        static let storeSize: CGFloat = 36
        static let storeRowHeight: CGFloat = 51
        static let minimumCardWidth: CGFloat = 150
        static let artworkHeight: CGFloat = 216
        static let compactArtworkHeight: CGFloat = 40
        static let artworkCornerRadius: CGFloat = 16
        static let priceFontSize: CGFloat = 28
        static let priceLineHeight: CGFloat = 34
        static let subtitleFontSize: CGFloat = 15
        static let subtitleLineHeight: CGFloat = 20
        static let sectionFontSize: CGFloat = 20
        static let sectionLineHeight: CGFloat = 25
        static let storeFontSize: CGFloat = 17
        static let storeLineHeight: CGFloat = 22
        static let availabilityFontSize: CGFloat = 12
        static let availabilityLineHeight: CGFloat = 16
        static let footerHorizontalInset: CGFloat = 21
        static let footerBottomInset: CGFloat = 4
    }
}

#Preview("Product") {
    @Previewable @StateObject var selection = ProductSelection()
    ProductDetailView(product: ProductMockData.products[0],
                      relatedProducts: ProductMockData.alternatives(for: ProductMockData.products[0].id), selection: selection)
}

#Preview("Product — dark, large text") {
    @Previewable @StateObject var selection = ProductSelection()
    ProductDetailView(product: ProductMockData.products[0],
                      relatedProducts: ProductMockData.alternatives(for: ProductMockData.products[0].id), selection: selection)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Product — specific store") {
    @Previewable @StateObject var selection = ProductSelection()
    let products = ProductMockData.productGroups[0].map { product in
        var scoped = product
        scoped.offers = Array(product.offers.prefix(1))
        return scoped
    }
    ProductDetailView(product: products[0], relatedProducts: Array(products.dropFirst()),
                      selection: selection, showsPricePrefix: false)
}
