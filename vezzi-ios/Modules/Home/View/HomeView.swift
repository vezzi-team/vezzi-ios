import SwiftUI

struct HomeView<Header: View>: View {
    let shelves: HomeShelves
    @ObservedObject var selection: ProductSelection
    let open: (Product, ProductOffer?) -> Void
    @ViewBuilder let header: Header
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) { header }
                sectionTitle(Texts.Home.Discovery.moti)
                MotiCollectionPager()
                if !shelves.deals.isEmpty { dealsShelf }
                if !shelves.essentials.isEmpty { essentialsGrid }
            }
            .padding(.bottom, 16)
            .frame(maxWidth: StorefrontScreen.maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private var dealsShelf: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(Texts.Home.Discovery.deals)
            ProductCarousel(products: shelves.deals, selection: selection, showsPricePrefix: false) { product in
                open(shelves.detailProduct(for: product), product.lowestOffer)
            }
            .accessibilityIdentifier(AccessibilityID.Home.deals)
        }
    }

    private var essentialsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Texts.Home.Discovery.essentials)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(shelves.essentials) { product in
                    ProductCard(product: product, quantity: quantity(for: product.id)) { open(product, nil) }
                }
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier(AccessibilityID.Home.essentials)
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize { return [GridItem(.flexible())] }
        return Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 2)
    }

    private func quantity(for id: String) -> Binding<Int> {
        Binding(get: { selection.quantity(for: id) }, set: { selection.setQuantity($0, for: id) })
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 16)
    }
}

struct HomeAdvertisingBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Texts.Home.Discovery.adTitle).font(.headline)
            Text(Texts.Home.Discovery.adSubtitle).font(.footnote).foregroundStyle(Color.Label.secondary)
            HStack {
                Text(Texts.Home.Discovery.adCaption)
                Image.System.arrowRight.accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Background.elevated, in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.Border.primary))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Home") {
    AppRootView(catalog: MockSearchRepository(), authentication: .preview())
}

#Preview("Catalog") {
    AppRootView(catalog: MockSearchRepository(), authentication: .preview(), initialTab: .catalog)
}
