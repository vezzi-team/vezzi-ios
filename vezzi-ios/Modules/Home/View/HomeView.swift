import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject var authentication: AuthenticationSession
    let profileTransition: Namespace.ID
    @EnvironmentObject private var router: AppRouter
    @State private var displayedCategory: ProductCategory?
    @State private var isPastResultsTop = false
    @State private var filterBarHeight: CGFloat = .zero
    @State private var showsAddress = false
    private let location: any DeviceLocating
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(repository: any CatalogRepository, authentication: AuthenticationSession, profileTransition: Namespace.ID,
         list: ShoppingListRepository, location: any DeviceLocating) {
        self.authentication = authentication
        self.profileTransition = profileTransition
        self.location = location
        _viewModel = StateObject(wrappedValue: HomeViewModel(repository: repository, list: list))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView { content(viewportHeight: geometry.size.height) }
                    .refreshable { await viewModel.refresh() }
                    .onChange(of: viewModel.selectedCategory) { _, _ in
                        showSelectedCategory(using: proxy)
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle { applySelectedCategory(using: proxy) }
                    }
                    .overlay(alignment: .bottom) {
                        scrollToTopButton(using: proxy)
                    }
            }
            .toolbar { navigationToolbar(availableWidth: geometry.size.width) }
        }
        .background(Color.Background.primary.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: selectedProduct) { product in
            ProductDetailView(product: product, relatedProducts: viewModel.relatedProducts,
                              selection: viewModel.selection)
        }
        .fullScreenCover(isPresented: $showsAddress) {
            LocationPickerView(coordinate: viewModel.list.origin, options: viewModel.list.routeOptions,
                               address: viewModel.list.originAddress, location: location, onConfirm: viewModel.list.setRoute)
        }
    }

    // MARK: - Content

    private func scrollToTopButton(using proxy: ScrollViewProxy) -> some View {
        ScrollToTopButton(isVisible: isPastResultsTop && !viewModel.products.isEmpty,
                          accessibilityIdentifier: AccessibilityID.Home.scrollToTop) {
            proxy.scrollTo(Const.scrollTopID, anchor: .top)
        }
        .padding(Const.contentInset)
        .frame(maxWidth: Const.maximumWidth, alignment: .trailing)
        .frame(maxWidth: .infinity)
    }

    private func showSelectedCategory(using proxy: ScrollViewProxy) {
        let displayedCount = viewModel.products(in: displayedCategory).count
        let shouldAnimate = !reduceMotion && isPastResultsTop && viewModel.filteredProducts.count < displayedCount
        guard shouldAnimate else {
            applySelectedCategory(using: proxy)
            return
        }

        // Keep the current feed until scrolling finishes so shrinking it cannot expose an empty viewport.
        withAnimation(.easeInOut(duration: Const.filterScrollDuration)) {
            proxy.scrollTo(Const.resultsTopID, anchor: .top)
        }
    }

    private func applySelectedCategory(using proxy: ScrollViewProxy) {
        guard displayedCategory != viewModel.selectedCategory else { return }
        if isPastResultsTop {
            proxy.scrollTo(Const.resultsTopID, anchor: .top)
        }
        displayedCategory = viewModel.selectedCategory
    }

    private func content(viewportHeight: CGFloat) -> some View {
        VStack(spacing: .zero) {
            // Let a large accessibility header scroll so the catalog remains reachable.
            if dynamicTypeSize.isAccessibilitySize { addressHeader }
            if !viewModel.products.isEmpty || viewModel.emptyState != .offline {
                catalogBanner
                    .padding(.horizontal, Const.contentInset)
                    .padding(.bottom, Const.sectionSpacing)
            }
            if viewModel.products.isEmpty {
                Spacer(minLength: .zero)
                emptyContent
                Spacer(minLength: .zero)
            } else {
                productSection(viewportHeight: viewportHeight)
            }
        }
        .frame(minHeight: viewModel.products.isEmpty ? viewportHeight : nil)
        .frame(maxWidth: Const.maximumWidth)
        .frame(maxWidth: .infinity)
        .id(Const.scrollTopID)
        .environment(\.isShimmerEnabled, viewModel.selectedProduct == nil && router.presentedSheet == nil && !showsAddress)
    }

    private func productSection(viewportHeight: CGFloat) -> some View {
        LazyVStack(spacing: .zero, pinnedViews: [.sectionHeaders]) {
            Section {
                productGrid
                    .padding(.horizontal, Const.contentInset)
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

    private var addressHeader: some View {
        addressPicker
            .padding(.horizontal, Const.contentInset)
            .padding(.top, Const.headerTopInset)
            .padding(.bottom, Const.headerBottomInset)
            .frame(maxWidth: Const.maximumWidth)
            .frame(maxWidth: .infinity)
    }

    private var categoryFilters: some View {
        HomeCategoryFilterBar(selectedCategory: $viewModel.selectedCategory, categories: viewModel.categories)
            .padding(.bottom, Const.gridHeaderSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
    }

    private var productGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Const.gridSpacing) {
            ForEach(viewModel.products(in: displayedCategory)) { product in
                ProductCard(product: product, quantity: quantityBinding(for: product.id)) {
                    viewModel.showProduct(product)
                }
                .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Const.filterTransitionDuration),
                   value: displayedCategory)
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: Const.minimumCardWidth), spacing: Const.gridSpacing, alignment: .top)]
    }

    // MARK: - Header

    @ToolbarContentBuilder
    private func navigationToolbar(availableWidth: CGFloat) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if !dynamicTypeSize.isAccessibilitySize {
                addressPicker
                    .buttonStyle(.plain)
                    // Give the title a stable width while reserving the profile's space.
                    // Leading bar items can be moved into the overflow menu on iOS 26.
                    .frame(width: max(.zero, availableWidth - Const.toolbarReservedWidth), alignment: .leading)
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if authentication.user != nil {
                    router.push(.profile, in: .home)
                } else {
                    router.presentAuthentication()
                }
            } label: {
                Label { Text(Texts.Profile.Main.title) } icon: { Image.System.person }
            }
            .tint(Color.Label.primary)
            .disabled(authentication.isRestoring || authentication.isSigningOut)
            .accessibilityIdentifier(AccessibilityID.Home.profile)
        }
        .matchedTransitionSource(id: AppRouter.Sheet.authentication, in: profileTransition)
    }

    private var addressPicker: some View {
        Button { showsAddress = true } label: {
            addressLabel
        }
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Home.address)
    }

    private var addressLabel: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(alignment: .firstTextBaseline, spacing: Const.chevronSpacing) {
                Text(viewModel.list.originAddress?.addressCapitalized ?? Texts.Routes.Settings.mapTitle)
                    .appTextStyle(size: Const.headingFontSize, lineHeight: Const.headingLineHeight,
                                   weight: .semibold, relativeTo: .headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : Const.addressMinimumScale)
                    .truncationMode(.middle)
                Image.System.chevronDown
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.Label.tertiary)
            }
            Text(Texts.Home.Main.nearbyStores)
                .appTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
    }

    private var catalogBanner: some View {
        CatalogStatusBanner(status: viewModel.catalogStatus, isCacheUnavailable: viewModel.isCacheUnavailable) {
            if viewModel.catalogStatus.failure == .authenticationRequired && !viewModel.catalogStatus.isOffline {
                router.presentAuthentication()
            } else {
                Task { await viewModel.refresh() }
            }
        }
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.emptyState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding()
        case .offline:
            MotiStateView.offline
                .accessibilityIdentifier(AccessibilityID.Home.offline)
        case .empty:
            MotiStateView(title: Texts.Search.emptyTitle, description: Texts.Search.emptyDescription)
                .accessibilityIdentifier(AccessibilityID.Home.empty)
        }
    }

    // MARK: - Bindings

    private var selectedProduct: Binding<Product?> {
        Binding(get: { viewModel.selectedProduct }, set: { _ in viewModel.dismissProduct() })
    }

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { viewModel.quantity(for: productID) },
            set: { viewModel.setQuantity($0, for: productID) }
        )
    }

    private enum Const {
        static let scrollTopID = "home.top"
        static let resultsTopID = "home.results.top"
        static let scrollTopTolerance: CGFloat = 1
        static let contentInset: CGFloat = 16
        static let maximumWidth: CGFloat = 760
        static let sectionSpacing: CGFloat = 11
        static let headerBottomInset: CGFloat = 8
        static let headerTopInset: CGFloat = 8
        static let gridHeaderSpacing: CGFloat = 12
        static let gridSpacing: CGFloat = 16
        static let filterScrollDuration: TimeInterval = 0.22
        static let filterTransitionDuration: TimeInterval = 0.18
        static let minimumCardWidth: CGFloat = 150
        static let addressMinimumScale: CGFloat = 0.7
        // Native side margins, the profile button and the gap between the two controls.
        static let toolbarReservedWidth: CGFloat = 92
        static let chevronSpacing: CGFloat = 14
        static let headingFontSize: CGFloat = 17
        static let headingLineHeight: CGFloat = 22
        static let captionFontSize: CGFloat = 13
        static let captionLineHeight: CGFloat = 18
    }
}

#Preview("Home — light") {
    @Previewable @Namespace var profileTransition
    NavigationStack {
        HomeView(repository: MockSearchRepository(), authentication: AuthenticationSession.preview(), profileTransition: profileTransition,
                 list: ShoppingListRepository(addressResolver: PreviewAddressResolver()), location: DeviceLocationService())
            .environmentObject(AppRouter())
    }
        .preferredColorScheme(.light)
}

#Preview("Home — dark, large text") {
    @Previewable @Namespace var profileTransition
    NavigationStack {
        HomeView(repository: MockSearchRepository(), authentication: AuthenticationSession.preview(), profileTransition: profileTransition,
                 list: ShoppingListRepository(addressResolver: PreviewAddressResolver()), location: DeviceLocationService())
            .environmentObject(AppRouter())
    }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
