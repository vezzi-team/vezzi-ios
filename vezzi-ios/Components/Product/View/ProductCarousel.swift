import SwiftUI

/// A horizontal shelf of the same cards used by the storefront and product details.
struct ProductCarousel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let products: [Product]
    @ObservedObject var selection: ProductSelection
    var showsStoreBadges = true
    var showsPricePrefix = true
    let open: (Product) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: ProductGridLayout.columnSpacing) {
                ForEach(products) { product in
                    ProductCard(product: product, promotion: product.promotion, showsStoreBadges: showsStoreBadges,
                                showsPricePrefix: showsPricePrefix, quantity: quantityBinding(for: product.id)) {
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
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(get: { selection.quantity(for: productID) },
                set: { selection.setQuantity($0, for: productID) })
    }

    private enum Const {
        static let shadowInset: CGFloat = 6
    }
}

#Preview("Product shelf") {
    @Previewable @StateObject var selection = ProductSelection()
    ProductCarousel(products: ProductMockData.products, selection: selection, open: { _ in })
        .background(Color.Background.primary)
}
