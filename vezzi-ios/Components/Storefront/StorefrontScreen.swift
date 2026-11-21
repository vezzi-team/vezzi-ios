import SwiftUI

struct StorefrontScreen: View {
    static let maximumContentWidth: CGFloat = 760

    @StateObject private var viewModel: StorefrontViewModel
    @ObservedObject var authentication: AuthenticationSession
    let storefrontTransition: Namespace.ID
    @EnvironmentObject private var router: AppRouter
    @State private var showsAddress = false
    private let location: any DeviceLocating
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let page: StorefrontPage

    init(page: StorefrontPage, repository: any CatalogRepository, authentication: AuthenticationSession, storefrontTransition: Namespace.ID,
         list: ShoppingListRepository, location: any DeviceLocating) {
        self.page = page
        self.authentication = authentication
        self.storefrontTransition = storefrontTransition
        self.location = location
        _viewModel = StateObject(wrappedValue: StorefrontViewModel(page: page, repository: repository, list: list))
    }

    var body: some View {
        GeometryReader { geometry in
            if case .collection(let collection) = page {
                collectionFeed(collection, viewportHeight: geometry.size.height)
            } else {
                feed(viewportHeight: geometry.size.height)
                    .screenStateFade(for: viewModel.hasProducts)
                    .toolbar { navigationToolbar(availableWidth: geometry.size.width) }
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // The scroll view can retain its refresh action after the cover is dismissed.
        .refreshable { [weak viewModel] in await viewModel?.refresh() }
        .environment(\.isShimmerEnabled, viewModel.selectedDetail == nil && router.presentedSheet == nil &&
                     ((page != .catalog && page != .home) || router.presentedCollection == nil) && !showsAddress)
        .background(Color.Background.primary.ignoresSafeArea())
        .sheet(item: selectedDetail) { detail in
            ProductDetailView(product: detail.product, relatedProducts: viewModel.relatedProducts,
                              selection: viewModel.selection, selectedOffer: detail.promotion,
                              selectedStoreTitle: Texts.Product.Stores.promotion)
                .environment(\.isShimmerEnabled, true)
        }
        .fullScreenCover(isPresented: $showsAddress) {
            LocationPickerView(coordinate: viewModel.list.origin, options: viewModel.list.routeOptions,
                               address: viewModel.list.originAddress, location: location, onConfirm: viewModel.list.setRoute)
        }
    }

    @ViewBuilder private func feed(viewportHeight: CGFloat) -> some View {
        if !viewModel.hasProducts {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    emptyContent
                        .screenStateFade(for: viewModel.emptyState)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: Self.maximumContentWidth, minHeight: viewportHeight)
                .frame(maxWidth: .infinity)
            }
        } else if page == .catalog {
            CatalogView(viewModel: viewModel, viewportHeight: viewportHeight, transition: storefrontTransition,
                        openCategory: { router.presentedCollection = .category($0) }) { header }
        } else {
            HomeView(shelves: viewModel.shelves, selection: viewModel.selection, open: viewModel.showProduct,
                     collectionTransition: storefrontTransition, openCollection: { router.presentedCollection = .moti($0) }) { header }
        }
    }

    @ViewBuilder private func collectionFeed(_ collection: StorefrontCollection, viewportHeight: CGFloat) -> some View {
        let feed = ScrollView {
            collectionContent(viewportHeight: viewportHeight)
                .screenStateFade(for: viewModel.products.isEmpty ? viewModel.emptyState : nil)
        }
        .accessibilityIdentifier(AccessibilityID.collectionProducts(collection))

        switch collection {
        case .category:
            feed.modifier(CategoryScrollControls(hasProducts: !viewModel.products.isEmpty))
        case .moti:
            feed.scrollIndicators(.hidden, axes: .vertical)
        }
    }

    @ViewBuilder private func collectionContent(viewportHeight: CGFloat) -> some View {
        if viewModel.products.isEmpty {
            emptyContent.frame(maxWidth: .infinity, minHeight: viewportHeight)
        } else {
            ProductGrid(products: viewModel.products, selection: viewModel.selection) { viewModel.showProduct($0) }
                .padding(Const.contentInset)
                .frame(maxWidth: Self.maximumContentWidth)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var header: some View {
        if dynamicTypeSize.isAccessibilitySize { addressHeader }
        if viewModel.hasProducts || viewModel.emptyState != .offline {
            Group {
                if showsStatusBanner {
                    catalogBanner
                } else {
                    HomeAdvertisingBanner()
                }
            }
            .padding(.horizontal, Const.contentInset)
            .padding(.bottom, page == .catalog ? Const.sectionSpacing : 0)
        }
    }

    private var showsStatusBanner: Bool {
        page == .catalog || !viewModel.hasProducts || viewModel.catalogStatus.isOffline ||
            viewModel.catalogStatus.failure != nil || viewModel.isCacheUnavailable
    }

    private var addressHeader: some View {
        addressPicker
            .padding(.horizontal, Const.contentInset)
            .padding(.top, Const.headerTopInset)
            .padding(.bottom, Const.headerBottomInset)
            .frame(maxWidth: Self.maximumContentWidth)
            .frame(maxWidth: .infinity)
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
                    router.push(.profile, in: page.tab)
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
            Task { await viewModel.refresh() }
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
            if case .collection(let collection) = page {
                let title = switch collection {
                case .category: Texts.Catalog.emptyCategory
                case .moti: Texts.Home.Discovery.emptyCollection
                }
                MotiStateView(title: title)
            } else {
                MotiStateView(title: Texts.Search.emptyTitle, description: Texts.Search.emptyDescription)
                    .accessibilityIdentifier(AccessibilityID.Home.empty)
            }
        }
    }

    // MARK: - Bindings

    private var selectedDetail: Binding<StorefrontProductDetail?> {
        Binding(get: { viewModel.selectedDetail }, set: { _ in viewModel.dismissProduct() })
    }

    private enum Const {
        static let contentInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 11
        static let headerBottomInset: CGFloat = 8
        static let headerTopInset: CGFloat = 8
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

private struct CategoryScrollControls: ViewModifier {
    let hasProducts: Bool
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
                                  accessibilityIdentifier: AccessibilityID.Catalog.categoryScrollToTop) {
                    position.scrollTo(edge: .top)
                }
                .padding(ProductGridLayout.contentInset)
            }
    }
}
