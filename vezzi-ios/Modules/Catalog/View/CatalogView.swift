import SwiftUI

struct CatalogView<Header: View>: View {
    @ObservedObject var viewModel: StorefrontViewModel
    let viewportHeight: CGFloat
    @ViewBuilder let header: Header
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedFilter: CatalogFilter
    @State private var isPastResultsTop = false
    @State private var filterBarHeight: CGFloat = .zero

    init(viewModel: StorefrontViewModel, viewportHeight: CGFloat, @ViewBuilder header: () -> Header) {
        self.viewModel = viewModel
        self.viewportHeight = viewportHeight
        self.header = header()
        _displayedFilter = State(initialValue: viewModel.selectedFilter)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content(viewportHeight: viewportHeight) }
                .onChange(of: viewModel.selectedFilter) { _, _ in
                    showSelectedFilter(using: proxy)
                }
                .onScrollPhaseChange { _, phase in
                    if phase == .idle { applySelectedFilter(using: proxy) }
                }
                .overlay(alignment: .bottom) {
                    scrollToTopButton(using: proxy)
                }
        }
    }

    private func scrollToTopButton(using proxy: ScrollViewProxy) -> some View {
        ScrollToTopButton(isVisible: isPastResultsTop && !viewModel.products.isEmpty,
                          accessibilityIdentifier: AccessibilityID.Catalog.scrollToTop) {
            proxy.scrollTo(Const.scrollTopID, anchor: .top)
        }
        .padding(Const.contentInset)
        .frame(maxWidth: StorefrontScreen.maximumContentWidth, alignment: .trailing)
        .frame(maxWidth: .infinity)
    }

    private func showSelectedFilter(using proxy: ScrollViewProxy) {
        let displayedCount = viewModel.products(in: displayedFilter).count
        let shouldAnimate = !reduceMotion && isPastResultsTop && viewModel.filteredProducts.count < displayedCount
        guard shouldAnimate else {
            applySelectedFilter(using: proxy)
            return
        }

        // Keep the current feed until scrolling finishes so shrinking it cannot expose an empty viewport.
        withAnimation(.easeInOut(duration: Const.filterScrollDuration)) {
            proxy.scrollTo(Const.resultsTopID, anchor: .top)
        }
    }

    private func applySelectedFilter(using proxy: ScrollViewProxy) {
        guard displayedFilter != viewModel.selectedFilter else { return }
        if isPastResultsTop {
            proxy.scrollTo(Const.resultsTopID, anchor: .top)
        }
        displayedFilter = viewModel.selectedFilter
    }

    private func content(viewportHeight: CGFloat) -> some View {
        VStack(spacing: .zero) {
            header
            productSection(viewportHeight: viewportHeight)
        }
        .frame(maxWidth: StorefrontScreen.maximumContentWidth)
        .frame(maxWidth: .infinity)
        .id(Const.scrollTopID)
    }

    private func productSection(viewportHeight: CGFloat) -> some View {
        LazyVStack(spacing: .zero, pinnedViews: [.sectionHeaders]) {
            Section {
                productGrid
                    .padding(.horizontal, ProductGridLayout.contentInset)
                    .padding(.bottom, Const.contentInset)
                    // A short filtered feed must still leave enough room to pin its header.
                    .frame(minHeight: max(.zero, viewportHeight - filterBarHeight), alignment: .top)
            } header: {
                categoryFilters
            }
        }
        // Keep the scroll target outside lazy children so it remains available offscreen.
        .id(Const.resultsTopID)
        .onGeometryChange(for: Bool.self) { geometry in
            geometry.frame(in: .scrollView(axis: .vertical)).minY < -Const.scrollTopTolerance
        } action: { isPastResultsTop = $0 }
    }

    private var categoryFilters: some View {
        CatalogCategoryFilterBar(selectedFilter: $viewModel.selectedFilter, categories: viewModel.categories)
            .padding(.bottom, Const.gridHeaderSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
    }

    private var productGrid: some View {
        LazyVGrid(columns: ProductGridLayout.columns(for: dynamicTypeSize), alignment: .leading, spacing: Const.gridSpacing) {
            ForEach(viewModel.products(in: displayedFilter)) { product in
                ProductCard(product: product, quantity: quantityBinding(for: product.id)) {
                    viewModel.showProduct(product)
                }
                .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Const.filterTransitionDuration),
                   value: displayedFilter)
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { viewModel.quantity(for: productID) },
            set: { viewModel.setQuantity($0, for: productID) }
        )
    }

}

private enum Const {
    static let scrollTopID = "catalog.top"
    static let resultsTopID = "catalog.results.top"
    static let scrollTopTolerance: CGFloat = 1
    static let contentInset: CGFloat = 16
    static let gridHeaderSpacing: CGFloat = 12
    static let gridSpacing: CGFloat = 16
    static let filterScrollDuration: TimeInterval = 0.22
    static let filterTransitionDuration: TimeInterval = 0.18
}
