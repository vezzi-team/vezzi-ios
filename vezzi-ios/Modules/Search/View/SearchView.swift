import SwiftUI

struct SearchView: View {
    @Environment(\.preferredShoppingMode) private var preferredMode
    @EnvironmentObject private var router: AppRouter
    @StateObject private var viewModel: SearchViewModel
    @ObservedObject private var selection: ProductSelection
    @State private var isSearching = false
    @State private var expandedSection: SearchSection?
    @Namespace private var sectionTransition
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isPastScrollTopThreshold = false
    @State private var viewportHeight: CGFloat = .zero
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(repository: any CatalogRepository, selection: ProductSelection? = nil,
         stores: [String: SearchStoreInfo] = [:], groupOrder: [String] = []) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(repository: repository, stores: stores, groupOrder: groupOrder))
        self.selection = selection ?? ProductSelection()
    }

    var body: some View {
        results
            .searchRefreshable(using: viewModel)
            .animation(reduceMotion ? nil : .screenStateFade) { content in
                content.background(viewModel.showsModePicker ? Color.Background.primary : Color.Background.iOSPrimary)
            }
            .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .navigationBar)
            .toolbar { searchToolbar }
            .safeAreaBar(edge: .top, spacing: .zero) {
                if viewModel.showsModePicker { modePicker }
            }
            .contentShape(.rect)
            .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
            .searchable(text: $viewModel.query, isPresented: $isSearching, prompt: Texts.Search.prompt)
            .searchPresentationToolbarBehavior(horizontalSizeClass == .regular ? .avoidHidingContent : .automatic)
            .searchFocused($isSearchFocused)
            .onChange(of: router.selectedTab == .search ? preferredMode : nil, initial: true) { _, mode in
                if let mode, viewModel.mode != mode { viewModel.mode = mode }
            }
            .onSubmit(of: .search) { isSearchFocused = false }
            .onReceive(router.willOpenShoppingList) {
                if viewModel.selectedProduct != nil { viewModel.dismissProduct() }
                expandedSection = nil
                isSearchFocused = false
                isSearching = false
            }
            .accessibilityHidden(expandedSection != nil)
            .modifier(SearchProductSheet(viewModel: viewModel, selection: selection, isPresenter: expandedSection == nil))
            .fullScreenCover(item: $expandedSection) { section in
                let cover = SearchSectionScreen(section: section, viewModel: viewModel, selection: selection)
                if reduceMotion {
                    cover
                } else {
                    cover.navigationTransition(.zoom(sourceID: section.id, in: sectionTransition))
                }
            }
    }

    // MARK: - Search Presentation

    @ToolbarContentBuilder
    private var searchToolbar: some ToolbarContent {
        if horizontalSizeClass == .regular && isSearching {
            ToolbarItem(placement: .cancellationAction) {
                Button(role: .cancel) { isSearching = false }
                    .accessibilityIdentifier(AccessibilityID.Search.cancel)
            }
        }
    }

    // MARK: - Modes

    private var modePicker: some View {
        Picker(Texts.Search.mode, selection: modeSelection) {
            ForEach(ShoppingMode.allCases) { mode in
                Text(mode == .cheaper ? Texts.Search.cheaper : Texts.Search.faster).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Const.contentInset)
        .padding(.top, Const.pickerTopInset)
        .padding(.bottom, Const.pickerBottomInset)
        .gesture(TouchDownObserver { pressed in
            if pressed { isSearchFocused = false }
        })
        .accessibilityIdentifier(AccessibilityID.Search.mode)
    }

    private var modeSelection: Binding<ShoppingMode> {
        Binding(get: { viewModel.mode }, set: { mode in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: Const.modeDuration)) {
                viewModel.mode = mode
            }
        })
    }

    // MARK: - Results

    private var results: some View {
        ScrollView {
            visibleResults
                .screenStateFade(for: viewModel.showsSections ? nil : viewModel.emptyState)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, height in
            viewportHeight = height
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Const.scrollTopThreshold
        } action: { _, isPastThreshold in
            isPastScrollTopThreshold = isPastThreshold
        }
        .onChange(of: viewModel.mode) { _, _ in
            isSearchFocused = false
            withTransaction(Transaction(animation: nil)) {
                scrollPosition.scrollTo(edge: .top)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onScrollPhaseChange(dismissSearchFocusOnScroll)
        .accessibilityIdentifier(AccessibilityID.Search.results)
        .overlay(alignment: .bottomTrailing) { scrollToTopButton }
        .animation(reduceMotion ? nil : .easeOut(duration: Const.resultsTransitionDuration),
                   value: viewModel.items.map(\.id))
        .environment(\.isShimmerEnabled, viewModel.selectedProduct == nil && expandedSection == nil)
    }

    @ViewBuilder private var visibleResults: some View {
        if !viewModel.showsSections {
            emptyContent.frame(maxWidth: .infinity, minHeight: viewportHeight)
        } else {
            ZStack(alignment: .topLeading) {
                resultsContent
                    .id(viewModel.mode)
                    .transition(resultsTransition)
            }
            .disabled(!viewModel.resultsMatchQuery)
            .accessibilityHidden(!viewModel.resultsMatchQuery)
        }
    }

    private var resultsContent: some View {
        LazyVStack(alignment: .leading, spacing: Const.sectionSpacing) {
            ForEach(viewModel.sections) { section in
                productSection(section)
                    .transition(resultsTransition)
            }
        }
        .padding(.bottom, Const.contentInset)
    }

    private var scrollToTopButton: some View {
        ScrollToTopButton(isVisible: isPastScrollTopThreshold && viewModel.showsSections,
                          accessibilityIdentifier: AccessibilityID.Search.scrollToTop) {
            isSearchFocused = false
            scrollPosition.scrollTo(edge: .top)
        }
        .padding(Const.contentInset)
    }

    private var resultsTransition: AnyTransition {
        reduceMotion ? .identity : AnyTransition(.blurReplace)
    }

    private func dismissSearchFocusOnScroll(_: ScrollPhase, _ phase: ScrollPhase) {
        if phase == .interacting { isSearchFocused = false }
    }

    private func productSection(_ section: SearchSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading(section)
                .padding(.horizontal, Const.contentInset)
            ProductCarousel(products: Array(section.products.prefix(ProductGridLayout.shelfPreviewLimit)), selection: selection,
                            showsStoreBadges: section.storeID == nil, showsPricePrefix: section.storeID == nil) { product in
                isSearchFocused = false
                viewModel.showProduct(product, storeID: section.storeID)
            }
            .onScrollPhaseChange(dismissSearchFocusOnScroll)
            if section.products.count > ProductGridLayout.shelfPreviewLimit {
                ProductSectionButton(title: Texts.Common.showMore) {
                    isSearchFocused = false
                    expandedSection = section
                }
                .accessibilityLabel(Text(verbatim: Texts.Search.showMore(in: section.title, address: section.address)))
                .accessibilityIdentifier(AccessibilityID.Search.showMore(section.id))
                .matchedTransitionSource(id: section.id, in: sectionTransition)
                .padding(.horizontal, Const.contentInset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Search.section(section.id))
    }

    private func sectionHeading(_ section: SearchSection) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Const.headingSpacing) {
                sectionTitle(section)
                Spacer(minLength: Const.headingSpacing)
                walkingTime(section)
            }
            VStack(alignment: .leading, spacing: Const.headingSpacing) {
                sectionTitle(section)
                walkingTime(section)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func sectionTitle(_ section: SearchSection) -> some View {
        HStack(alignment: .top, spacing: Const.storeSpacing) {
            if section.storeID != nil {
                StoreLogoPlaceholder()
                    .frame(width: Const.storeSize, height: Const.storeSize)
            }
            sectionLabels(section)
        }
    }

    private func sectionLabels(_ section: SearchSection) -> some View {
        VStack(alignment: .leading, spacing: Const.headingSpacing) {
            Text(section.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.Label.primary)
            if let address = section.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(address)
                    .appTextStyle(size: Const.addressFontSize, lineHeight: Const.addressLineHeight, relativeTo: .caption)
                    .foregroundStyle(Color.Label.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func walkingTime(_ section: SearchSection) -> some View {
        if let minutes = section.walkingMinutes {
            Text(Texts.Search.walkingTime(minutes))
                .font(.caption)
                .foregroundStyle(Color.Label.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.emptyState {
        case .loading:
            ProgressView()
        case .offline:
            MotiStateView.offline
                .accessibilityIdentifier(AccessibilityID.Search.offline)
        case .empty:
            MotiStateView(
                title: emptyTitle,
                description: viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Texts.Search.emptyDescription : Texts.Search.noResultsDescription)
                .accessibilityIdentifier(AccessibilityID.Search.empty)
        }
    }

    private var emptyTitle: String {
        if !viewModel.items.isEmpty { return Texts.Search.noOffers }
        return viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Texts.Search.emptyTitle : Texts.Search.noResultsTitle
    }

    private enum Const {
        static let scrollTopThreshold: CGFloat = 200
        static let contentInset: CGFloat = 16
        static let pickerTopInset: CGFloat = 8
        static let pickerBottomInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 14
        static let headingSpacing: CGFloat = 4
        static let storeSpacing: CGFloat = 10
        static let storeSize: CGFloat = 24
        static let addressFontSize: CGFloat = 13
        static let addressLineHeight: CGFloat = 18
        static let modeDuration: TimeInterval = 0.2
        static let resultsTransitionDuration: TimeInterval = 0.18
    }
}

extension View {
    @ViewBuilder
    func searchRefreshable(using viewModel: SearchViewModel) -> some View {
        if viewModel.canRefresh {
            refreshable { [weak viewModel] in await viewModel?.refresh() }
        } else {
            self
        }
    }
}

#Preview("Search — light") {
    NavigationStack {
        SearchView(repository: MockSearchRepository(), stores: SearchMockData.stores, groupOrder: SearchMockData.groupOrder)
    }
    .preferredColorScheme(.light)
    .environmentObject(AppRouter())
}

#Preview("Search — dark, large text") {
    NavigationStack {
        SearchView(repository: MockSearchRepository(), stores: SearchMockData.stores, groupOrder: SearchMockData.groupOrder)
    }
    .preferredColorScheme(.dark)
    .environmentObject(AppRouter())
    .dynamicTypeSize(.accessibility3)
}

#Preview("Search — empty catalog") {
    NavigationStack { SearchView(repository: PreviewCatalogRepository()) }
        .environmentObject(AppRouter())
}

#Preview("Search — offline, empty catalog") {
    @Previewable @State var repository = DefaultCatalogRepository()
    NavigationStack { SearchView(repository: repository) }
        .environmentObject(AppRouter())
        .task { repository.updateConnectivity(isConnected: false) }
}
