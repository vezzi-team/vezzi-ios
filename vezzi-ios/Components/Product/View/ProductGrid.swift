import SwiftUI

struct ProductGrid: View {
    let products: [Product]
    @ObservedObject var selection: ProductSelection
    let open: (Product) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Const.rowSpacing) {
            ForEach(products) { product in
                ProductCard(product: product, quantity: quantity(for: product.id)) { open(product) }
            }
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        return Array(repeating: GridItem(.flexible(), spacing: Const.columnSpacing, alignment: .top), count: 2)
    }

    private func quantity(for id: String) -> Binding<Int> {
        Binding(get: { selection.quantity(for: id) }, set: { selection.setQuantity($0, for: id) })
    }

    private enum Const {
        static let rowSpacing: CGFloat = 10
        static let columnSpacing: CGFloat = 16
    }
}
