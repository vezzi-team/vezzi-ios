import SwiftUI

struct SearchSectionScreen: View {
    let section: SearchSection
    @ObservedObject var viewModel: SearchViewModel
    let selection: ProductSelection
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let current = viewModel.sections.first { $0.id == section.id && $0.storeID == section.storeID }
        NavigationStack {
            ScrollView {
                if let current {
                    ProductGrid(products: current.products, selection: selection,
                                showsStoreBadges: current.storeID == nil, showsPricePrefix: current.storeID == nil) {
                        viewModel.showProduct($0, storeID: current.storeID)
                    }
                    .padding(ProductGridLayout.contentInset)
                    .frame(maxWidth: StorefrontScreen.maximumContentWidth)
                    .frame(maxWidth: .infinity)
                } else {
                    MotiStateView(title: Texts.Search.noResultsTitle)
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.vertical)
                }
            }
            .searchRefreshable(using: viewModel)
            .modifier(ProductGridScrollControls(hasProducts: current != nil, identifier: AccessibilityID.Search.scrollToTop))
            .environment(\.isShimmerEnabled, viewModel.selectedProduct == nil)
            .background(Color.Background.primary.ignoresSafeArea())
            .navigationTitle(current?.title ?? section.title)
            .toolbar {
                if let address = current?.address, !address.isEmpty {
                    ToolbarItem(placement: .subtitle) { Text(address) }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .tint(Color.Label.primary)
                        .accessibilityIdentifier(AccessibilityID.Search.closeSection)
                }
            }
        }
        // Reserve a downward pull for refresh while this full-screen section is open.
        .interactiveDismissDisabled(viewModel.canRefresh)
        .modifier(SearchProductSheet(viewModel: viewModel, selection: selection))
    }
}

struct SearchProductSheet: ViewModifier {
    @ObservedObject var viewModel: SearchViewModel
    let selection: ProductSelection
    var isPresenter = true

    func body(content: Content) -> some View {
        let product = Binding(get: { isPresenter ? viewModel.selectedProduct : nil },
                              set: { _ in viewModel.dismissProduct() })
        content.sheet(item: product) { product in
            ProductDetailView(product: product, relatedProducts: viewModel.relatedProducts, selection: selection,
                              showsPricePrefix: viewModel.selectedProductStoreID == nil)
        }
    }
}
