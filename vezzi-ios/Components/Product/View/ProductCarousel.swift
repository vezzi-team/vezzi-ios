import SwiftUI

/// A horizontal shelf of the same cards used by the storefront and product details.
struct ProductCarousel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let products: [Product]
    @ObservedObject var selection: ProductSelection
    var showsStoreBadges = true
    var showsPricePrefix = true
    var revealsNextCard = false
    let open: (Product) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: revealsNextCard ? Const.previewSpacing : ProductGridLayout.columnSpacing) {
                ForEach(products) { product in
                    ProductCard(product: product, promotion: product.promotion, showsStoreBadges: showsStoreBadges,
                                showsPricePrefix: showsPricePrefix, quantity: $selection[productID: product.id]) {
                        open(product)
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in
                        ProductGridLayout.cardWidth(in: width, for: dynamicTypeSize)
                    }
                    .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Const.shadowInset)
        }
        .contentMargins(.horizontal, ProductGridLayout.contentInset, for: .scrollContent)
        .scrollIndicators(.hidden, axes: .horizontal)
        .scrollTargetBehavior(.viewAligned)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum Const {
        // Tighter gaps reveal the following card while retaining the grid's card width.
        static let previewSpacing: CGFloat = 6
        static let shadowInset: CGFloat = 6
    }
}

#Preview("Product shelf") {
    @Previewable @StateObject var selection = ProductSelection()
    ProductCarousel(products: ProductMockData.products, selection: selection, open: { _ in })
        .background(Color.Background.primary)
}
