import SwiftUI

struct ShoppingListView: View {
    @StateObject private var viewModel: ShoppingListViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsStores = false
    @State private var showsAddress = false
    @State private var summaryHeight: CGFloat = .zero
    @State private var viewportHeight: CGFloat = .zero
    @State private var addressHeight: CGFloat = .zero
    @State private var summaryTop: CGFloat = .zero
    @State private var isPastSummaryTop = false
    @ScaledMetric(relativeTo: .subheadline) private var metricTextHeight = Const.metricTextHeight

    init(catalog: any CatalogRepository, list: ShoppingListRepository) {
        _viewModel = StateObject(wrappedValue: ShoppingListViewModel(catalog: catalog, list: list))
    }

    var body: some View {
        ScrollView { content }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // The container already excludes the native top and bottom bars.
            geometry.containerSize.height
        } action: { _, height in
            viewportHeight = height
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            let threshold = summaryTop + (isPastSummaryTop ? -Const.summaryPinTolerance : Const.summaryPinTolerance)
            return summaryTop > .zero && geometry.contentOffset.y + geometry.contentInsets.top > threshold
        } action: { _, isPastTop in
            isPastSummaryTop = isPastTop
        }
        .environment(\.isShimmerEnabled, viewModel.selectedProduct == nil && viewModel.routePlan == nil && !showsStores)
        .background(Color.Background.iOSPrimary.ignoresSafeArea())
        .navigationTitle(Texts.ShoppingList.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .safeAreaBar(edge: .bottom) {
            if viewModel.contentState == .products || viewModel.contentState == .empty { bottomAction }
        }
        .refreshable { await viewModel.refresh() }
        .onAppear { viewModel.list.setPresented(true) }
        .onDisappear { viewModel.list.setPresented(false) }
        .sheet(item: selectedProduct) { product in
            ProductDetailView(product: product, relatedProducts: viewModel.relatedProducts, selection: viewModel.list.selection,
                              selectedOffer: viewModel.selectedProductOffer)
        }
        .sheet(item: $viewModel.routePlan) { plan in ShoppingRouteView(plan: plan) }
        .alert(Texts.ShoppingList.addressTitle, isPresented: $showsAddress) {
            Button(Texts.ShoppingList.understood, role: .cancel) {}
        } message: { Text(Texts.ShoppingList.addressDescription) }
    }

    // MARK: - Header

    private var content: some View {
        // A lazy root preserves the native inline-large title's spacing at accessibility text sizes.
        LazyVStack(alignment: .leading, spacing: Const.sectionSpacing) {
            addressButton
                .padding(.horizontal, viewModel.contentState == .products ? Const.contentInset : Const.routeHorizontalInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { addressHeight = $0 }
            if viewModel.contentState == .products {
                modePicker.padding(.horizontal, Const.contentInset)
                summarySection
            } else {
                VStack(spacing: Const.sectionSpacing) {
                    emptyContent
                    feedback.padding(.horizontal, Const.routeHorizontalInset)
                }
                .frame(maxWidth: .infinity,
                       minHeight: max(.zero, viewportHeight - addressHeight - Const.sectionSpacing - Const.contentInset * 2))
            }
        }
        .padding(.vertical, Const.contentInset)
        .frame(maxWidth: Const.maximumWidth)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: Const.contentCoordinateSpace)
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.contentState {
        case .loading:
            ProgressView()
        case .offline:
            MotiEmptyStateView.offline
                .accessibilityIdentifier(AccessibilityID.ShoppingList.offline)
        case .unavailable:
            VStack(spacing: Const.sectionSpacing) {
                MotiEmptyStateView(title: Texts.ShoppingList.loadErrorTitle,
                                   description: Texts.ShoppingList.loadError)
                if viewModel.needsAuthentication {
                    Button(Texts.ShoppingList.signIn) { router.presentAuthentication() }
                        .buttonStyle(.glass)
                }
            }
        case .empty:
            MotiEmptyStateView(title: Texts.ShoppingList.emptyTitle, description: Texts.ShoppingList.emptyDescription,
                               expression: .winking)
                .accessibilityIdentifier(AccessibilityID.ShoppingList.empty)
        case .products:
            EmptyView()
        }
    }

    private var summarySection: some View {
        LazyVStack(alignment: .leading, spacing: Const.sectionSpacing, pinnedViews: pinsSummary ? [.sectionHeaders] : []) {
            Section {
                VStack(alignment: .leading, spacing: Const.sectionSpacing) {
                    planStatus
                    feedback
                    productSection
                }
                .padding(.horizontal, Const.contentInset)
                // Let short lists reach the summary's pinned position.
                .frame(minHeight: max(.zero, viewportHeight - summaryHeight), alignment: .top)
            } header: {
                summary
            }
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            // This anchor stays at the section's start, independently of the pinned header's height.
            geometry.frame(in: .named(Const.contentCoordinateSpace)).minY
        } action: { summaryTop = $0 }
    }

    private var addressButton: some View {
        Button { showsAddress = true } label: {
            HStack(spacing: Const.addressSpacing) {
                Image.System.walk.font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: Const.captionSpacing) {
                    Text(Texts.ShoppingList.mockAddress).font(.subheadline.weight(.semibold)).foregroundStyle(Color.Label.primary)
                    Text(Texts.ShoppingList.walking).font(.caption).foregroundStyle(Color.Label.secondary)
                }
                Spacer(minLength: .zero)
                Image.System.chevronRight.font(.caption.weight(.semibold)).foregroundStyle(Color.Label.secondary)
            }
            .padding(Const.addressInset)
            .background(Color.Background.secondary, in: .rect(cornerRadius: Const.addressRadius))
        }
        .buttonStyle(.plain)
        .pressScaleEffect()
        .accessibilityIdentifier(AccessibilityID.ShoppingList.address)
    }

    private var modePicker: some View {
        Picker(Texts.Search.mode, selection: modeSelection) {
            Text(Texts.Search.cheaper).tag(ShoppingListMode.cheaper)
            Text(Texts.Search.faster).tag(ShoppingListMode.faster)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.mode)
    }

    private var modeSelection: Binding<ShoppingListMode> {
        Binding(get: { viewModel.mode }, set: { mode in
            withAnimation(reduceMotion ? nil : .smooth(duration: Const.transitionDuration)) {
                viewModel.mode = mode
            }
        })
    }

    private var summary: some View {
        // Keep the section's layout height expanded while only the visible panel collapses.
        priceSummary(isCompact: false)
            .hidden()
            .accessibilityHidden(true)
            .environment(\.isShimmerEnabled, false)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            .overlay(alignment: .top) {
                priceSummary(isCompact: pinsSummary && isPastSummaryTop)
            }
            .padding(.horizontal, Const.contentInset)
            .padding(.vertical, Const.summaryVerticalInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { summaryHeight = $0 }
    }

    private func priceSummary(isCompact: Bool) -> some View {
        ShoppingListPriceSummary(total: viewModel.plan?.total, comparison: viewModel.comparisonPrice,
                                 mode: viewModel.mode, isLoading: viewModel.list.isBusy,
                                 isCompact: isCompact)
    }

    private var pinsSummary: Bool {
        // Leave at least half of the unobscured viewport for the products.
        summaryHeight > .zero && summaryHeight <= viewportHeight * Const.maximumPinnedHeightFraction
    }

    // MARK: - Plan

    private var planStatus: some View {
        // Reserve the wrapped label's height in both states without keeping a hidden spinner alive.
        loadingMessage
            .padding(.leading, Const.loadingIndicatorWidth + Const.loadingSpacing)
            .hidden()
            .frame(maxWidth: .infinity, minHeight: metricTextHeight + Const.metricVerticalInset * 2)
            .overlay {
                if let plan = viewModel.plan {
                    planMetrics(plan)
                        .transition(modeTransition)
                } else if viewModel.list.isBusy {
                    loadingStatus
                        .transition(modeTransition)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: viewModel.list.isBusy)
            .animation(reduceMotion ? nil : .easeInOut(duration: Const.transitionDuration), value: viewModel.plan != nil)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.ShoppingList.planStatus)
    }

    private var loadingStatus: some View {
        HStack(spacing: Const.loadingSpacing) {
            ProgressView()
                .frame(width: Const.loadingIndicatorWidth)
                .accessibilityHidden(true)
            loadingMessage
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.loading)
    }

    private var loadingMessage: some View {
        Text(Texts.ShoppingList.updating)
            .font(.footnote)
            .foregroundStyle(Color.Label.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func planMetrics(_ plan: ShoppingPlan) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Const.metricSpacing) {
                if viewModel.mode == .cheaper, let savings = viewModel.priceSavings, savings > 0 {
                    metric(Texts.ShoppingList.savings(savings), highlighted: true)
                        .transition(modeTransition)
                } else if viewModel.mode == .faster, viewModel.savedMinutes > 0 {
                    metric(Texts.ShoppingList.faster(viewModel.savedMinutes), highlighted: true)
                        .transition(modeTransition)
                }
                Button { showsStores = true } label: {
                    HStack(spacing: Const.captionSpacing) {
                        Text(Texts.ShoppingList.stores(plan.stops.count))
                            .contentTransition(reduceMotion ? .identity : .opacity)
                        Image.System.chevronDown
                    }
                }
                .buttonStyle(.glass)
                .tint(Color.Label.primary)
                .accessibilityIdentifier(AccessibilityID.ShoppingList.stores)
                .popover(isPresented: $showsStores) {
                    ShoppingPlanStoresView(stops: plan.stops)
                        .presentationCompactAdaptation(.popover)
                }
                metric(Texts.ShoppingList.minutes(Int(ceil(Double(plan.totalSeconds) / Const.secondsPerMinute))))
                metric(Measurement(value: Double(plan.walkingMeters), unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
            }
            .font(.subheadline.weight(.medium))
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func metric(_ title: String, highlighted: Bool = false) -> some View {
        Text(title)
            .contentTransition(reduceMotion ? .identity : .opacity)
            .padding(.horizontal, Const.metricHorizontalInset)
            .padding(.vertical, Const.metricVerticalInset)
            .foregroundStyle(highlighted ? Color.Label.white : Color.Label.primary)
            .glassEffect(highlighted ? .regular.tint(.accentColor) : .regular, in: .capsule)
    }

    @ViewBuilder private var feedback: some View {
        if let message = viewModel.message {
            VStack(alignment: .leading, spacing: Const.summarySpacing) {
                Text(message).font(.footnote).foregroundStyle(Color.Label.secondary)
                if !viewModel.list.isBusy, viewModel.needsAuthentication {
                    Button(Texts.ShoppingList.signIn) { router.presentAuthentication() }
                        .buttonStyle(.glass)
                }
            }
            .accessibilityIdentifier(AccessibilityID.ShoppingList.feedback)
        }
    }

    private var bottomAction: some View {
        Button {
            if viewModel.contentState == .empty {
                router.popToRoot(in: .home)
                router.selectTab(.home)
            }
            else { viewModel.routePlan = viewModel.plan }
        } label: {
            Text(viewModel.contentState == .empty ? Texts.ShoppingList.findProducts : Texts.ShoppingList.showRoute)
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(viewModel.contentState == .products && viewModel.plan == nil)
        .padding(.horizontal, Const.routeHorizontalInset)
        .padding(.vertical, Const.routeInset)
        .frame(maxWidth: Const.maximumWidth)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(viewModel.contentState == .empty
                                 ? AccessibilityID.ShoppingList.addProducts : AccessibilityID.ShoppingList.route)
    }

    // MARK: - Products

    private var productSection: some View {
        VStack(alignment: .leading, spacing: Const.summarySpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(Texts.ShoppingList.cart).font(.headline)
                Spacer()
                Text(Texts.ShoppingList.products(viewModel.list.selection.quantities.count))
                    .font(.caption).foregroundStyle(Color.Label.secondary)
            }
            productGrid
        }
    }

    private var productGrid: some View {
        LazyVGrid(columns: columns, spacing: Const.gridSpacing) {
            ForEach(viewModel.products) { product in
                ProductCard(product: product, showsPricePrefix: viewModel.plan == nil, quantity: quantity(for: product.id)) {
                    viewModel.showProduct(product)
                }
                .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Const.transitionDuration), value: viewModel.list.selection.quantities.keys.sorted())
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Const.gridSpacing), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var modeTransition: AnyTransition {
        reduceMotion ? .identity : AnyTransition(.blurReplace)
    }

    private func quantity(for id: String) -> Binding<Int> {
        Binding(get: { viewModel.list.selection.quantity(for: id) }, set: { viewModel.list.selection.setQuantity($0, for: id) })
    }

    private var selectedProduct: Binding<Product?> {
        Binding(get: { viewModel.selectedProduct }, set: { _ in viewModel.dismissProduct() })
    }

    private enum Const {
        static let contentCoordinateSpace = "shoppingList.content"
        static let contentInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let maximumWidth: CGFloat = 760
        static let addressSpacing: CGFloat = 10
        static let addressInset: CGFloat = 12
        static let addressRadius: CGFloat = 16
        static let captionSpacing: CGFloat = 2
        static let summarySpacing: CGFloat = 8
        static let summaryVerticalInset: CGFloat = 8
        static let maximumPinnedHeightFraction: CGFloat = 0.5
        static let summaryPinTolerance: CGFloat = 4
        static let metricSpacing: CGFloat = 8
        static let metricTextHeight: CGFloat = 20
        static let metricHorizontalInset: CGFloat = 10
        static let metricVerticalInset: CGFloat = 8
        static let loadingIndicatorWidth: CGFloat = 20
        static let loadingSpacing: CGFloat = 8
        static let secondsPerMinute = 60.0
        static let routeHorizontalInset: CGFloat = 20
        static let routeInset: CGFloat = 8
        static let gridSpacing: CGFloat = 16
        static let transitionDuration: TimeInterval = 0.25
    }
}

#Preview("Shopping list") {
    @Previewable @StateObject var list = ShoppingListPreview.repository()
    NavigationStack {
        ShoppingListView(catalog: PreviewCatalogRepository(snapshot: ShoppingListPreview.snapshot), list: list)
    }
    .environmentObject(AppRouter())
    .task { list.setAccount(ShoppingListPreview.account) }
}

#Preview("Shopping list — dark, large text") {
    @Previewable @StateObject var list = ShoppingListPreview.repository()
    NavigationStack {
        ShoppingListView(catalog: PreviewCatalogRepository(snapshot: ShoppingListPreview.snapshot), list: list)
    }
    .environmentObject(AppRouter())
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
    .task { list.setAccount(ShoppingListPreview.account) }
}

#Preview("Shopping list — guest") {
    NavigationStack {
        ShoppingListView(catalog: PreviewCatalogRepository(), list: ShoppingListRepository())
    }
    .environmentObject(AppRouter())
}
