import SwiftUI

struct ShoppingListView: View {
    @StateObject private var viewModel: ShoppingListViewModel
    private let location: any DeviceLocating
    private let isRestoringAccount: Bool
    @Environment(\.preferredShoppingMode) private var preferredMode
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsStores = false
    @State private var showsActiveTripAlert = false
    @State private var showsAddress = false
    @State private var summaryHeight: CGFloat = .zero
    @State private var viewportHeight: CGFloat = .zero
    @State private var addressHeight: CGFloat = .zero
    @State private var summaryTop: CGFloat = .zero
    @State private var isPastSummaryTop = false
    @ScaledMetric(relativeTo: .subheadline) private var metricTextHeight = Const.metricTextHeight

    init(catalog: any CatalogRepository, list: ShoppingListRepository, location: (any DeviceLocating)? = nil,
         isRestoringAccount: Bool = false) {
        _viewModel = StateObject(wrappedValue: ShoppingListViewModel(catalog: catalog, list: list))
        self.location = location ?? DeviceLocationService()
        self.isRestoringAccount = isRestoringAccount
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
        .environment(\.isShimmerEnabled, isListVisible)
        .background(Color.Background.primary.ignoresSafeArea())
        .navigationTitle(Texts.ShoppingList.title)
        .toolbarTitleDisplayMode(.inlineLarge)
        .onReceive(router.willOpenShoppingList) {
            if viewModel.selectedProduct != nil { viewModel.dismissProduct() }
            if router.pendingShoppingPlanID == nil { viewModel.routes = nil }
            showsAddress = false
            showsStores = false
        }
        .onChange(of: viewModel.activityDestination(for: router.pendingShoppingPlanID, isRestoringAccount: isRestoringAccount),
                  initial: true) { _, destination in
            guard let destination else { return }
            router.clearShoppingProgressRequest()
            switch destination {
            case .progress: viewModel.showRoutes(startsAtSummary: viewModel.list.trip?.pendingFinish != nil)
            case .list: viewModel.routes = nil
            }
        }
        .safeAreaBar(edge: .bottom) {
            if viewModel.contentState == .products || viewModel.contentState == .empty { bottomAction }
        }
        .onChange(of: router.selectedTab == .shoppingList ? preferredMode : nil, initial: true) { _, mode in
            if let mode, viewModel.mode != mode { viewModel.mode = mode }
        }
        .refreshable { [weak viewModel] in await viewModel?.refresh() }
        .onAppear { viewModel.list.setPresented(true) }
        .onDisappear { if viewModel.routes == nil { viewModel.list.setPresented(false) } }
        .sheet(item: selectedProduct) { product in
            ProductDetailView(product: product, loadAlternatives: viewModel.alternatives, selection: viewModel.list.selection,
                              selectedOffer: viewModel.selectedProductOffer)
        }
        .fullScreenCover(item: $viewModel.routes) { snapshot in
            ShoppingRouteView(snapshot: snapshot, list: viewModel.list, location: location)
        }
        .fullScreenCover(isPresented: $showsAddress) {
            LocationPickerView(coordinate: viewModel.list.origin, options: viewModel.list.routeOptions,
                               address: viewModel.list.originAddress, location: location, onConfirm: viewModel.list.setRoute)
        }
        .environment(\.shoppingPlanMedia, viewModel.planMedia)
    }

    // MARK: - Header

    private var isListVisible: Bool {
        viewModel.selectedProduct == nil && viewModel.routes == nil && !showsStores && !showsAddress
    }

    private var content: some View {
        // A lazy root preserves the native inline-large title's spacing at accessibility text sizes.
        LazyVStack(alignment: .leading, spacing: Const.sectionSpacing) {
            addressButton
                .padding(.horizontal, viewModel.contentState == .products ? Const.contentInset : TabBarActionLayout.horizontalInset)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { addressHeight = $0 }
            if viewModel.list.showsDeletedCartNotice {
                HStack {
                    Text(Texts.Trip.cartAlreadyDeleted)
                        .font(.footnote).foregroundStyle(Color.Label.secondary)
                    Spacer(minLength: 8)
                    Button(Texts.ShoppingList.understood) { viewModel.list.showsDeletedCartNotice = false }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, Const.contentInset)
            }
            listBody.screenStateFade(for: viewModel.contentState)
        }
        .padding(.vertical, Const.contentInset)
        .frame(maxWidth: TabBarActionLayout.maximumWidth)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: Const.contentCoordinateSpace)
    }

    @ViewBuilder private var listBody: some View {
        if let trip = viewModel.list.trip {
            VStack(alignment: .leading, spacing: Const.sectionSpacing) {
                shoppingProgress(trip)
                ProductSectionButton(title: Texts.Trip.finish) { viewModel.showRoutes(startsAtSummary: true) }
                    .accessibilityIdentifier(AccessibilityID.Trip.review)
                productSection
            }
            .padding(.horizontal, Const.contentInset)
        } else if viewModel.contentState == .products {
            VStack(spacing: Const.sectionSpacing) {
                modePicker.padding(.horizontal, Const.contentInset)
                summarySection
            }
        } else {
            VStack(spacing: Const.sectionSpacing) {
                emptyContent
                feedback.padding(.horizontal, TabBarActionLayout.horizontalInset)
            }
            .frame(maxWidth: .infinity,
                   minHeight: max(.zero, viewportHeight - addressHeight - Const.sectionSpacing - Const.contentInset * 2))
        }
    }

    private func shoppingProgress(_ trip: ShoppingTrip) -> some View {
        let bought = trip.boughtCount
        let total = trip.items.count
        let money = Decimal.FormatStyle.Currency(code: "RUB").precision(.fractionLength(0...2))
        let spent = trip.spent
        let count = Texts.Trip.progressCount(bought, total)
        let amount = Texts.Trip.progressAmount(spent.formatted(money), trip.plan.total.formatted(money))
        let countLabel = Text(count).font(.headline)
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(bought)))
        let priceLabel = Text(amount).font(.subheadline).foregroundStyle(.secondary)
            .contentTransition(reduceMotion ? .identity : .numericText(value: NSDecimalNumber(decimal: spent).doubleValue))
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    countLabel.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    priceLabel.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) { countLabel; priceLabel }
            }
            GeometryReader { bounds in
                Capsule().fill(Color.Label.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: bounds.size.width * CGFloat(bought) / CGFloat(max(1, total)))
                    }
            }
            .frame(height: 6)
            .padding(.bottom, 8)
        }
        .monospacedDigit()
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.Background.elevated, in: .rect(cornerRadius: 24))
        .shadow(color: Color.Shadow.primary.opacity(0.08), radius: 12, y: 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: bought)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count)
        .accessibilityValue(amount)
    }

    @ViewBuilder private var emptyContent: some View {
        switch viewModel.contentState {
        case .loading:
            ProgressView()
        case .offline:
            MotiStateView.offline
                .accessibilityIdentifier(AccessibilityID.ShoppingList.offline)
        case .unavailable:
            MotiStateView(title: Texts.ShoppingList.loadErrorTitle, description: Texts.ShoppingList.loadError)
        case .empty:
            MotiStateView(title: Texts.ShoppingList.emptyTitle, description: Texts.ShoppingList.emptyDescription,
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
                    if viewModel.plan != nil || viewModel.list.isBusy {
                        planStatus
                    }
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
                    Text(viewModel.list.originAddress?.addressCapitalized ?? Texts.Routes.Settings.mapTitle)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.Label.primary)
                    Text(Texts.Routes.Settings.walkingMode(viewModel.list.routeOptions)).font(.caption).foregroundStyle(Color.Label.secondary)
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
            Text(Texts.Search.cheaper).tag(ShoppingMode.cheaper)
            Text(Texts.Search.faster).tag(ShoppingMode.faster)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.ShoppingList.mode)
    }

    private var modeSelection: Binding<ShoppingMode> {
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
        let message = viewModel.message
        let showsSignIn = viewModel.needsAuthentication && !viewModel.list.isBusy
            && (message != nil || viewModel.contentState == .unavailable)
        if message != nil || showsSignIn {
            VStack(alignment: .leading, spacing: Const.summarySpacing) {
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Color.Label.secondary)
                }
                if showsSignIn { signInButton }
            }
            .accessibilityIdentifier(AccessibilityID.ShoppingList.feedback)
        }
    }

    private var signInButton: some View {
        PrimaryActionButton(title: Texts.ShoppingList.signIn, action: router.presentAuthentication)
    }

    private var bottomAction: some View {
        ShoppingRouteButton(placement: .bottomBar) {
            if viewModel.contentState == .empty && viewModel.list.trip == nil {
                router.popToRoot(in: .catalog)
                router.selectTab(.catalog)
            } else {
                viewModel.showRoutes()
            }
        } label: {
            Text(viewModel.list.trip != nil ? Texts.Trip.resume :
                    (viewModel.contentState == .empty ? Texts.ShoppingList.findProducts : Texts.ShoppingList.showRoute))
                .contentTransition(reduceMotion ? .identity : .opacity)
                .animation(reduceMotion ? nil : .screenStateFade, value: viewModel.contentState == .empty)
        }
        .disabled(viewModel.list.trip == nil && viewModel.contentState == .products && viewModel.plan == nil)
        .accessibilityIdentifier(viewModel.list.trip != nil ? AccessibilityID.Trip.resume :
                                    (viewModel.contentState == .empty ? AccessibilityID.ShoppingList.addProducts : AccessibilityID.ShoppingList.route))
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
        .activeShoppingTripAlert(isPresented: $showsActiveTripAlert)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Const.gridSpacing), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var modeTransition: AnyTransition {
        reduceMotion ? .identity : AnyTransition(.blurReplace)
    }

    private func quantity(for id: String) -> Binding<Int> {
        viewModel.list.selection.quantityBinding(for: id, activeTripAlert: $showsActiveTripAlert)
    }

    private var selectedProduct: Binding<Product?> {
        Binding(get: { viewModel.selectedProduct }, set: { _ in viewModel.dismissProduct() })
    }

    private enum Const {
        static let contentCoordinateSpace = "shoppingList.content"
        static let contentInset: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
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
    @Previewable @StateObject var list = ShoppingListRepository()
    NavigationStack {
        ShoppingListView(catalog: PreviewCatalogRepository(snapshot: ShoppingListPreview.snapshot), list: list)
    }
    .environmentObject(AppRouter())
    .task {
        for product in ProductMockData.products.prefix(2) {
            list.selection.setQuantity(1, for: product.id)
        }
    }
}
