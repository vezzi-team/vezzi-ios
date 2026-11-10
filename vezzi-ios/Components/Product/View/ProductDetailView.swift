import SwiftUI

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    let product: Product
    let relatedProducts: [Product]
    let selection: ProductSelection
    var showsPricePrefix = true
    var selectedOffer: ProductOffer? = nil

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
                          selection: selection, showsPricePrefix: showsPricePrefix,
                          selectedOffer: product.id == self.product.id ? selectedOffer : nil) { alternative in
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllStores = false
    @AppStorage(Const.storeSortPreferenceKey) private var storeSort: ProductStoreSort = .priceAscending
    @State private var productNameBottom: CGFloat = .zero
    @State private var showsProductNameInNavigationBar = false

    let product: Product
    let relatedProducts: [Product]
    @ObservedObject var selection: ProductSelection
    let showsPricePrefix: Bool
    let selectedOffer: ProductOffer?
    let selectProduct: (Product) -> Void

    var body: some View {
        productList
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationHeader }
            .safeAreaBar(edge: .bottom, spacing: .zero) { bottomActions }
    }

    // MARK: - Navigation Header

    private var productBrand: String {
        product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var navigationTitle: String {
        if showsProductNameInNavigationBar { return product.displayName }
        return productBrand.isEmpty ? product.displayName : productBrand
    }

    private var navigationSubtitle: String {
        let components = showsProductNameInNavigationBar ? [productBrand, product.package] : [product.package]
        return components.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var navigationHeader: some ToolbarContent {
        ToolbarItem(placement: .title) {
            Text(navigationTitle)
                .font(.headline)
                .foregroundStyle(Color.Label.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.Product.Detail.navigationTitle)
        }
        ToolbarItem(placement: .subtitle) {
            Text(navigationSubtitle)
                .font(.caption)
                .foregroundStyle(Color.Label.secondary)
                .lineLimit(1, reservesSpace: true)
                .accessibilityIdentifier(AccessibilityID.Product.Detail.navigationSubtitle)
        }
    }

    // MARK: - Product

    private var productList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Const.rowSpacing) {
                productSummary
                if let selectedOffer {
                    selectedStoreSection(selectedOffer)
                }
                if !nearbyOffers.isEmpty {
                    storesSection
                }
                if !alternatives.isEmpty {
                    sectionHeading(Texts.Product.alternatives)
                        .padding(.top, Const.sectionSpacing - Const.rowSpacing)
                    alternativeProducts
                        .padding(.bottom, Const.contentInset)
                }
            }
            .padding(.horizontal, Const.contentInset)
            .coordinateSpace(name: Const.contentCoordinateSpace)
        }
        .scrollIndicators(.hidden)
        .background(Color.Background.elevated)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            productNameBottom > .zero && geometry.contentOffset.y + geometry.contentInsets.top >= productNameBottom
        } action: { _, isAboveVisibleContent in
            showsProductNameInNavigationBar = isAboveVisibleContent
        }
    }

    private var productSummary: some View {
        VStack(alignment: .leading, spacing: Const.summarySpacing) {
            artworkPlaceholder
            productName
            priceSummary
        }
        .padding(.top, Const.rowSpacing)
        .padding(.bottom, Const.sectionSpacing - Const.rowSpacing)
    }

    private var productName: some View {
        Text(product.displayName)
            .appTextStyle(size: Const.nameFontSize, lineHeight: Const.nameLineHeight,
                           weight: .semibold, relativeTo: .title3)
            .foregroundStyle(Color.Label.primary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(AccessibilityID.Product.Detail.name)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .named(Const.contentCoordinateSpace)).maxY
            } action: { productNameBottom = $0 }
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
            if let offer = selectedOffer ?? product.lowestOffer {
                ProductPriceLabel(price: offer.price, currency: offer.currency,
                                  showsPrefix: selectedOffer == nil && showsPricePrefix)
                    .appTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                                   weight: .bold, relativeTo: .title)
                    .accessibilityIdentifier(AccessibilityID.Product.Detail.price)
            }
            Text(Texts.Product.inStores(nearbyOffers.count + (selectedOffer == nil ? 0 : 1)))
                .appTextStyle(size: Const.subtitleFontSize, lineHeight: Const.subtitleLineHeight, relativeTo: .subheadline)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    // MARK: - Stores

    private func selectedStoreSection(_ offer: ProductOffer) -> some View {
        VStack(alignment: .leading, spacing: Const.rowSpacing) {
            sectionHeading(Texts.Product.Stores.selected)
            offerRow(offer)
                .padding(Const.selectedStoreInset)
                .overlay {
                    RoundedRectangle(cornerRadius: Const.selectedStoreRadius)
                        .strokeBorder(Color.accentColor, lineWidth: Const.selectedStoreBorderWidth)
                }
        }
        .padding(.bottom, Const.sectionSpacing - Const.rowSpacing)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Product.Detail.selectedStore)
    }

    private var nearbyOffers: [ProductOffer] {
        product.offers.filter { $0.storeID != selectedOffer?.storeID }
    }

    private var storesSection: some View {
        VStack(alignment: .leading, spacing: Const.rowSpacing) {
            offersHeading
            ForEach(visibleOffers) { offer in
                offerRow(offer)
                    .transition(reduceMotion ? .identity : .opacity)
            }
            if nearbyOffers.count > Const.initialStoreCount {
                storesExpansionButton
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: Const.storeSortDuration), value: storeSort)
    }

    private var visibleOffers: ArraySlice<ProductOffer> {
        storeSort.sorted(nearbyOffers, distance: ProductDetailMockDistances.distance)
            .prefix(showsAllStores ? nearbyOffers.count : Const.initialStoreCount)
    }

    private var storesExpansionButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: Const.storeExpansionDuration)) {
                showsAllStores.toggle()
            }
        } label: {
            Label {
                Text(showsAllStores ? Texts.Product.Stores.showLess : Texts.Product.Stores.showMore)
                    .contentTransition(.opacity)
            } icon: {
                Image.System.chevronDown
                    .rotationEffect(.degrees(showsAllStores ? Const.expandedChevronRotation : .zero))
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .sensoryFeedback(.impact(weight: .light), trigger: showsAllStores)
        .accessibilityIdentifier(AccessibilityID.Product.Detail.toggleStores)
    }

    private var offersHeading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Const.storeSpacing) {
                sectionHeading(Texts.Product.availableNearby)
                    .fixedSize()
                Spacer(minLength: .zero)
                storeSortMenu
            }
            VStack(alignment: .leading, spacing: Const.rowSpacing) {
                sectionHeading(Texts.Product.availableNearby)
                    .fixedSize(horizontal: false, vertical: true)
                storeSortMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.bottom, Const.headingBottomInset)
    }

    private var storeSortMenu: some View {
        Menu {
            Picker(Texts.Product.Stores.Sort.title, selection: $storeSort) {
                ForEach(ProductStoreSort.allCases, id: \.self) { sort in
                    Label { Text(sort.title) } icon: { sort.image }
                        .tag(sort)
                        .accessibilityIdentifier(AccessibilityID.Product.Detail.sortOption(sort.rawValue))
                }
            }
        } label: {
            HStack(spacing: Const.sortLabelSpacing) {
                Image.System.arrowUpArrowDown
                Text(storeSort.title)
                    .contentTransition(.opacity)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .fixedSize()
        .tint(Color.Label.primary)
        .disabled(nearbyOffers.count < Const.minimumSortableStoreCount)
        .accessibilityLabel(Texts.Product.Stores.Sort.title)
        .accessibilityValue(storeSort.title)
        .accessibilityIdentifier(AccessibilityID.Product.Detail.sortStores)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .appTextStyle(size: Const.sectionFontSize, lineHeight: Const.sectionLineHeight,
                           weight: .semibold, relativeTo: .title3)
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
    }

    private func offerRow(_ offer: ProductOffer) -> some View {
        HStack(alignment: .top, spacing: Const.storeSpacing) {
            storeIcon
            storeSummary(offer)
        }
        .padding(.vertical, Const.rowVerticalInset)
        .frame(minHeight: Const.storeRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Product.Detail.store(offer.storeID))
    }

    private func storeHeading(_ offer: ProductOffer) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Const.storeSpacing) {
                storeName(offer)
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: .zero)
                storePrice(offer)
                    .fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: Const.storeTextSpacing) {
                storeName(offer)
                storePrice(offer)
            }
        }
    }

    private func storeName(_ offer: ProductOffer) -> some View {
        Text(offer.storeTitle)
            .appTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                           weight: .semibold, relativeTo: .headline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var storeIcon: some View {
        StoreLogoPlaceholder()
            .frame(width: Const.storeSize, height: Const.storeSize)
    }

    private func storeSummary(_ offer: ProductOffer) -> some View {
        VStack(alignment: .leading, spacing: Const.storeTextSpacing) {
            storeHeading(offer)
            if let address = offer.displayAddress {
                Text(address)
                    .appTextStyle(size: Const.addressFontSize, lineHeight: Const.addressLineHeight, relativeTo: .caption)
                    .foregroundStyle(Color.Label.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(offerSubtitle(offer))
                .appTextStyle(size: Const.availabilityFontSize, lineHeight: Const.availabilityLineHeight, relativeTo: .caption)
                .foregroundStyle(Color.Label.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let price = offer.cardPrice {
                Text(Texts.Catalog.cardPrice(price.formatted(.currency(code: offer.currency).locale(locale))))
                    .font(.caption)
                    .foregroundStyle(Color.Label.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let conditions = offer.priceConditions, !conditions.isEmpty {
                Text(conditions)
                    .font(.caption)
                    .foregroundStyle(Color.Label.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func offerSubtitle(_ offer: ProductOffer) -> String {
        let availability = offer.inStock.map { $0 ? Texts.Product.inStock : Texts.Product.outOfStock }
        let distance = ProductDetailMockDistances.distance(for: offer)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided).locale(locale))
        return [availability, distance, offer.isFresh ? nil : Texts.Catalog.stalePrice].compactMap { $0 }.joined(separator: " · ")
    }

    private func storePrice(_ offer: ProductOffer) -> some View {
        Text(offer.price, format: .currency(code: offer.currency).precision(.fractionLength(0...2)))
            .appTextStyle(size: Const.storeFontSize, lineHeight: Const.storeLineHeight,
                           weight: .semibold, relativeTo: .headline)
            .fixedSize(horizontal: false, vertical: true)
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
        static let contentCoordinateSpace = "product.detail.content"
        static let storeSortPreferenceKey = "product.storeSort"
        static let initialStoreCount = 3
        static let minimumSortableStoreCount = 2
        static let storeExpansionDuration: TimeInterval = 0.35
        static let storeSortDuration: TimeInterval = 0.3
        static let sortLabelSpacing: CGFloat = 2
        static let expandedChevronRotation: Double = 180
        static let contentInset: CGFloat = 16
        static let rowSpacing: CGFloat = 8
        static let summarySpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 16
        static let headingBottomInset: CGFloat = 2
        static let storeSpacing: CGFloat = 12
        static let storeTextSpacing: CGFloat = 4
        static let rowVerticalInset: CGFloat = 4
        static let storeSize: CGFloat = 36
        static let storeRowHeight: CGFloat = 51
        static let selectedStoreInset: CGFloat = 12
        static let selectedStoreRadius: CGFloat = 16
        static let selectedStoreBorderWidth: CGFloat = 1.5
        static let minimumCardWidth: CGFloat = 150
        static let artworkHeight: CGFloat = 226
        static let compactArtworkHeight: CGFloat = 120
        static let artworkCornerRadius: CGFloat = 10
        static let nameFontSize: CGFloat = 20
        static let nameLineHeight: CGFloat = 22
        static let priceFontSize: CGFloat = 28
        static let priceLineHeight: CGFloat = 34
        static let subtitleFontSize: CGFloat = 15
        static let subtitleLineHeight: CGFloat = 20
        static let sectionFontSize: CGFloat = 20
        static let sectionLineHeight: CGFloat = 25
        static let storeFontSize: CGFloat = 17
        static let storeLineHeight: CGFloat = 22
        static let addressFontSize: CGFloat = 13
        static let addressLineHeight: CGFloat = 18
        static let availabilityFontSize: CGFloat = 12
        static let availabilityLineHeight: CGFloat = 16
        static let footerHorizontalInset: CGFloat = 21
        static let footerBottomInset: CGFloat = 4
    }
}

private extension ProductStoreSort {
    var image: Image {
        switch self {
        case .priceAscending: Image.System.priceDecrease
        case .priceDescending: Image.System.priceIncrease
        case .distanceAscending: Image.System.arrowsInward
        case .distanceDescending: Image.System.arrowsOutward
        }
    }

    var title: String {
        switch self {
        case .priceAscending: Texts.Product.Stores.Sort.priceAscending
        case .priceDescending: Texts.Product.Stores.Sort.priceDescending
        case .distanceAscending: Texts.Product.Stores.Sort.distanceAscending
        case .distanceDescending: Texts.Product.Stores.Sort.distanceDescending
        }
    }
}

/// Temporary presentation-only distances until map integration; stable for each store across detail pages.
nonisolated private enum ProductDetailMockDistances {
    private static let meters: [Double] = [350, 500, 800]

    static func distance(for offer: ProductOffer) -> Measurement<UnitLength> {
        if let distance = offer.distance { return distance }
        let index = offer.storeID.utf8.reduce(0) { ($0 + Int($1)) % meters.count }
        return Measurement(value: meters[index], unit: .meters)
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

#Preview("Product — selected store") {
    @Previewable @StateObject var selection = ProductSelection()
    let product = ProductMockData.products[0]
    ProductDetailView(product: product, relatedProducts: ProductMockData.alternatives(for: product.id),
                      selection: selection, selectedOffer: product.offers[1])
}

#Preview("Product — selected store, large text") {
    @Previewable @StateObject var selection = ProductSelection()
    let product = ProductMockData.products[0]
    ProductDetailView(product: product, relatedProducts: ProductMockData.alternatives(for: product.id),
                      selection: selection, selectedOffer: product.offers[1])
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Product — more stores") {
    @Previewable @StateObject var selection = ProductSelection()
    var product = ProductMockData.products[0]
    product.offers.append(ProductOffer(id: "preview.extra.offer", storeID: "preview.extra.store",
                                       name: Texts.Search.Mock.perekrestok, price: 109,
                                       address: Texts.Home.Mock.workAddress))
    return ProductDetailView(product: product, relatedProducts: ProductMockData.alternatives(for: product.id),
                             selection: selection)
}
