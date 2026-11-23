import SwiftUI

struct HomeView<Header: View>: View {
    let shelves: HomeShelves
    let selection: ProductSelection
    let open: (Product, ProductOffer?) -> Void
    let collectionTransition: Namespace.ID
    let openCollection: (MotiCollection) -> Void
    @ViewBuilder let header: Header

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 0) { header }
                sectionTitle(Texts.Home.Discovery.moti)
                MotiCollectionPager(transition: collectionTransition, open: openCollection)
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
            ProductCarousel(products: shelves.deals, selection: selection,
                            showsPricePrefix: false) { product in
                open(product, product.promotion?.offer)
            }
            .accessibilityIdentifier(AccessibilityID.Home.deals)
        }
    }

    private var essentialsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(Texts.Home.Discovery.essentials)
            ProductGrid(products: shelves.essentials, selection: selection) { open($0, nil) }
                .padding(.horizontal, ProductGridLayout.contentInset)
                .accessibilityIdentifier(AccessibilityID.Home.essentials)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.Label.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 16)
    }
}

#Preview("Home") {
    AppRootView(catalog: MockSearchRepository(), authentication: .preview())
}

#Preview("Catalog") {
    AppRootView(catalog: MockSearchRepository(), authentication: .preview(), initialTab: .catalog)
}
