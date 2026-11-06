import SwiftUI

struct HomeProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []
    let product: HomeProduct
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        NavigationStack(path: $path) {
            productPage(for: product)
                .toolbar { dismissToolbar }
                .navigationDestination(for: String.self) { productID in
                    if let product = viewModel.product(for: productID) {
                        productPage(for: product)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Const.sheetCornerRadius)
    }

    // MARK: - Navigation

    private func productPage(for product: HomeProduct) -> some View {
        HomeProductDetailPage(product: product, viewModel: viewModel) { alternative in
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
            Label { Text(Texts.Home.Product.close) } icon: { Image.System.xmark }
        }
        .tint(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Home.ProductDetail.close)
    }

    private enum Const {
        static let sheetCornerRadius: CGFloat = 34
    }
}

private struct HomeProductDetailPage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let product: HomeProduct
    @ObservedObject var viewModel: HomeViewModel
    let selectProduct: (HomeProduct) -> Void

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
                    sectionHeading(Texts.Home.Product.alternatives)
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
            if let price = product.lowestPrice {
                HomePriceLabel(price: price)
                    .onestTextStyle(size: Const.priceFontSize, lineHeight: Const.priceLineHeight,
                                   weight: .bold, relativeTo: .title)
            }
            Text(Texts.Home.Product.inStores(product.offers.count))
                .onestTextStyle(size: Const.subtitleFontSize, lineHeight: Const.subtitleLineHeight, relativeTo: .subheadline)
                .foregroundStyle(Color.Label.secondary)
        }
    }

    // MARK: - Stores

    private var offersHeading: some View {
        sectionHeading(Texts.Home.Product.availableNearby)
            .padding(.bottom, Const.headingBottomInset)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .onestTextStyle(size: Const.sectionFontSize, lineHeight: Const.sectionLineHeight,
                           weight: .semibold, relativeTo: .title3)
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
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
        .frame(minHeight: Const.storeRowHeight)
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

    // MARK: - Alternatives

    private var alternatives: [HomeProduct] {
        viewModel.alternatives(for: product.id)
    }

    private var alternativeProducts: some View {
        LazyVGrid(columns: alternativeColumns, alignment: .leading, spacing: Const.contentInset) {
            ForEach(alternatives) { alternative in
                HomeProductCard(product: alternative, quantity: quantityBinding(for: alternative.id)) {
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
        HomeProductActions(productName: product.name, quantity: quantityBinding(for: product.id))
            .padding(.horizontal, Const.footerHorizontalInset)
            .padding(.top, Const.rowSpacing)
            .padding(.bottom, Const.footerBottomInset)
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { viewModel.quantity(for: productID) },
            set: { viewModel.setQuantity($0, for: productID) }
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
    @Previewable @StateObject var viewModel = HomeViewModel()
    HomeProductDetailView(product: HomeMockData.products[0], viewModel: viewModel)
}

#Preview("Product — dark, large text") {
    @Previewable @StateObject var viewModel = HomeViewModel()
    HomeProductDetailView(product: HomeMockData.products[0], viewModel: viewModel)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
