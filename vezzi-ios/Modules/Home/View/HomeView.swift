import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @ObservedObject var authentication: AuthenticationSession
    let profileTransition: Namespace.ID
    @EnvironmentObject private var router: AppRouter
    @State private var selectedProduct: HomeProduct?
    @State private var displayedCategory: HomeProductCategory?
    @State private var isPastResultsTop = false
    @State private var filterBarHeight: CGFloat = .zero
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView { content(viewportHeight: geometry.size.height) }
                    .onChange(of: viewModel.selectedCategory) { _, _ in
                        showSelectedCategory(using: proxy)
                    }
                    .onScrollPhaseChange { _, phase in
                        if phase == .idle { applySelectedCategory(using: proxy) }
                    }
            }
        }
        .background(Color.Background.primary.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navigationToolbar }
        .sheet(item: $selectedProduct) { product in
            HomeProductDetailView(product: product, viewModel: viewModel)
        }
        .sensoryFeedback(.selection, trigger: viewModel.quantities)
    }

    // MARK: - Content

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
            dinnerCard
                .padding(.horizontal, Const.contentInset)
                .padding(.bottom, Const.sectionSpacing)
            productSection(viewportHeight: viewportHeight)
        }
        .frame(maxWidth: Const.maximumWidth)
        .frame(maxWidth: .infinity)
        .environment(\.isShimmerEnabled, selectedProduct == nil && router.presentedSheet == nil)
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
        HomeCategoryFilterBar(selectedCategory: $viewModel.selectedCategory)
            .padding(.bottom, Const.gridHeaderSpacing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterBarHeight = $0 }
    }

    private var productGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Const.gridSpacing) {
            ForEach(viewModel.products(in: displayedCategory)) { product in
                HomeProductCard(product: product, quantity: quantityBinding(for: product.id)) {
                    selectedProduct = product
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
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !dynamicTypeSize.isAccessibilitySize {
                addressPicker
                    .buttonStyle(.plain)
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
            .accessibilityIdentifier(AccessibilityID.Home.profile)
        }
        .matchedTransitionSource(id: AppRouter.Sheet.authentication, in: profileTransition)
    }

    private var addressPicker: some View {
        Menu {
            Picker(Texts.Home.Main.address, selection: $viewModel.selectedAddress) {
                ForEach(HomeAddress.allCases) { address in
                    Text(address.title).tag(address)
                }
            }
        } label: {
            addressLabel
        }
        .foregroundStyle(Color.Label.primary)
        .accessibilityIdentifier(AccessibilityID.Home.address)
    }

    private var addressLabel: some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(alignment: .firstTextBaseline, spacing: Const.chevronSpacing) {
                Text(viewModel.selectedAddress.title)
                    .onestTextStyle(size: Const.headingFontSize, lineHeight: Const.headingLineHeight,
                                   weight: .semibold, relativeTo: .headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Image.System.chevronDown
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.Label.tertiary)
            }
            Text(Texts.Home.Main.nearbyStores)
                .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .contentShape(.rect)
    }

    private var dinnerCard: some View {
        Button(action: viewModel.addDinnerProducts) {
            dinnerContent
                .padding(.horizontal, Const.dinnerHorizontalInset)
                .padding(.vertical, Const.dinnerVerticalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.Background.elevated, in: .rect(cornerRadius: Const.dinnerCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Const.dinnerCornerRadius)
                    .strokeBorder(Color.Border.primary, lineWidth: Const.borderWidth))
                .shadow(color: Color.Shadow.primary.opacity(Const.shadowOpacity), radius: Const.shadowRadius, y: Const.shadowOffset)
        }
        .pressScaleEffect()
        .disabled(viewModel.hasDinnerProducts)
        .accessibilityIdentifier(AccessibilityID.Home.addDinner)
    }

    private var dinnerContent: some View {
        VStack(alignment: .leading, spacing: Const.dinnerSpacing) {
            Text(Texts.Home.Main.dinnerTitle)
                .onestTextStyle(size: Const.headingFontSize, lineHeight: Const.headingLineHeight,
                               weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Color.Label.primary)
            Text(Texts.Home.Main.dinnerSubtitle)
                .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight, relativeTo: .footnote)
                .foregroundStyle(Color.Label.secondary)
            dinnerActionLabel
        }
        .multilineTextAlignment(.leading)
    }

    private var dinnerActionLabel: some View {
        HStack(spacing: Const.actionSpacing) {
            Text(viewModel.hasDinnerProducts ? Texts.Home.Main.dinnerAdded : Texts.Home.Main.collectProducts)
            viewModel.hasDinnerProducts ? Image.System.checkmark : Image.System.arrowRight
        }
        .onestTextStyle(size: Const.captionFontSize, lineHeight: Const.captionLineHeight,
                       weight: .semibold, relativeTo: .footnote)
        .foregroundStyle(Color.accentColor)
    }

    // MARK: - Bindings

    private func quantityBinding(for productID: String) -> Binding<Int> {
        Binding(
            get: { viewModel.quantity(for: productID) },
            set: { viewModel.setQuantity($0, for: productID) }
        )
    }

    private enum Const {
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
        static let chevronSpacing: CGFloat = 14
        static let headingFontSize: CGFloat = 17
        static let headingLineHeight: CGFloat = 22
        static let captionFontSize: CGFloat = 13
        static let captionLineHeight: CGFloat = 18
        static let dinnerSpacing: CGFloat = 4
        static let dinnerHorizontalInset: CGFloat = 16
        static let dinnerVerticalInset: CGFloat = 16
        static let dinnerCornerRadius: CGFloat = 16
        static let actionSpacing: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let shadowOpacity: Double = 0.05
        static let shadowRadius: CGFloat = 6
        static let shadowOffset: CGFloat = 4
    }
}

#Preview("Home — light") {
    @Previewable @Namespace var profileTransition
    NavigationStack {
        HomeView(authentication: AuthenticationSession(), profileTransition: profileTransition)
            .environmentObject(AppRouter())
    }
        .preferredColorScheme(.light)
}

#Preview("Home — dark, large text") {
    @Previewable @Namespace var profileTransition
    NavigationStack {
        HomeView(authentication: AuthenticationSession(), profileTransition: profileTransition)
            .environmentObject(AppRouter())
    }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
