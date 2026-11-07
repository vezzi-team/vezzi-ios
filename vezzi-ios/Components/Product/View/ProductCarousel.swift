import SwiftUI

/// A horizontal shelf of the same cards used by the storefront and product details.
struct ProductCarousel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let products: [Product]
    @ObservedObject var selection: ProductSelection
    var showsStoreBadges = true
    let open: (Product) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Const.spacing) {
                ForEach(products) { product in
                    ProductCard(product: product, showsStoreBadges: showsStoreBadges,
                                showsPricePrefix: showsStoreBadges, quantity: quantityBinding(for: product.id)) {
                        open(product)
                    }
                    .frame(width: cardWidth)
                    .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Const.shadowInset)
        }
        .contentMargins(.horizontal, Const.contentInset, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? Const.accessibleCardWidth : Const.cardWidth
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(get: { selection.quantity(for: productID) },
                set: { selection.setQuantity($0, for: productID) })
    }

    private enum Const {
        static let cardWidth: CGFloat = 177
        static let accessibleCardWidth: CGFloat = 280
        static let spacing: CGFloat = 16
        static let contentInset: CGFloat = 16
        static let shadowInset: CGFloat = 6
    }
}

#Preview("Product shelf") {
    @Previewable @StateObject var selection = ProductSelection()
    ProductCarousel(products: ProductMockData.products, selection: selection, open: { _ in })
        .background(Color.Background.primary)
}
