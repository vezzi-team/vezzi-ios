import SwiftUI

enum ProductGridLayout {
    static let shelfPreviewLimit = 4
    static let contentInset: CGFloat = 16
    static let columnSpacing: CGFloat = 16
    private static let minimumCardWidth: CGFloat = 150

    static func columns(for textSize: DynamicTypeSize) -> [GridItem] {
        let size: GridItem.Size = textSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: minimumCardWidth)
        return [GridItem(size, spacing: columnSpacing, alignment: .top)]
    }

    /// The horizontal scroll container supplies the width inside its content margins.
    static func cardWidth(in contentWidth: CGFloat, for textSize: DynamicTypeSize) -> CGFloat {
        guard !textSize.isAccessibilitySize else { return contentWidth }
        let count = max(1, floor((contentWidth + columnSpacing) / (minimumCardWidth + columnSpacing)))
        return (contentWidth - (count - 1) * columnSpacing) / count
    }
}

struct ProductGrid: View {
    let products: [Product]
    @ObservedObject var selection: ProductSelection
    var showsStoreBadges = true
    var showsPricePrefix = true
    let open: (Product) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: ProductGridLayout.columns(for: dynamicTypeSize), alignment: .leading, spacing: Const.rowSpacing) {
            ForEach(products) { product in
                ProductCard(product: product, showsStoreBadges: showsStoreBadges, showsPricePrefix: showsPricePrefix,
                            quantity: $selection[productID: product.id]) { open(product) }
            }
        }
    }

    private enum Const {
        static let rowSpacing: CGFloat = 10
    }
}

struct ProductGridScrollControls: ViewModifier {
    let hasProducts: Bool
    let identifier: String
    @State private var position = ScrollPosition(edge: .top)
    @State private var isPastTop = false

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicatorsFlash(onAppear: true)
            .pauseShimmerWhileScrolling()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 200
            } action: { _, isPastTop in self.isPastTop = isPastTop }
            .overlay(alignment: .bottomTrailing) {
                ScrollToTopButton(isVisible: hasProducts && isPastTop,
                                  accessibilityIdentifier: identifier) {
                    position.scrollTo(edge: .top)
                }
                .padding(ProductGridLayout.contentInset)
            }
    }
}
