import SwiftUI

/// Composes the app's modules and owns state shared across tabs.
struct AppRootView: View {
    @StateObject private var preferences: ShoppingPreferences
    @StateObject private var appRouter: AppRouter
    @ObservedObject private var productSelection: ProductSelection
    private let shoppingList: ShoppingListRepository
    private let location: any DeviceLocating
    @ObservedObject private var authentication: AuthenticationSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var storefrontTransition
    private let catalog: any CatalogRepository
    private let contentScale: CGFloat

    init(
        catalog: any CatalogRepository,
        authentication: AuthenticationSession,
        shoppingList: ShoppingListRepository? = nil,
        location: (any DeviceLocating)? = nil,
        initialTab: AppRouter.Tab = .home,
        contentScale: CGFloat = Const.defaultContentScale
    ) {
        self.catalog = catalog
        self.authentication = authentication
        _preferences = StateObject(wrappedValue: ShoppingPreferences(authentication: authentication))
        let list = shoppingList ?? ShoppingListRepository()
        self.shoppingList = list
        self.location = location ?? DeviceLocationService()
        self.productSelection = list.selection
        self.contentScale = contentScale
        _appRouter = StateObject(wrappedValue: AppRouter(selectedTab: initialTab))
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab(value: AppRouter.Tab.home) {
                navigationStack(for: .home)
            } label: {
                tabLabel(for: .home)
            }

            Tab(value: AppRouter.Tab.shoppingList) {
                navigationStack(for: .shoppingList)
            } label: {
                tabLabel(for: .shoppingList)
            }

            Tab(value: AppRouter.Tab.catalog) {
                navigationStack(for: .catalog)
            } label: {
                tabLabel(for: .catalog)
            }

            Tab(value: AppRouter.Tab.search, role: .search) {
                navigationStack(for: .search)
            } label: {
                tabLabel(for: .search)
            }
        }
        // Also gives the search tab its detached appearance on iOS 27.
        .tabViewSearchActivation(.searchTabSelection)
        .accessibilityHidden(appRouter.presentedCover != nil)
        .tint(.accentColor)
        .sensoryFeedback(.selection, trigger: productSelection.feedbackRevision)
        .alert(Texts.ShoppingList.limitTitle, isPresented: $productSelection.showsLimitAlert) {
            Button(Texts.ShoppingList.understood, role: .cancel) {}
        } message: { Text(Texts.ShoppingList.limitDescription) }
        .sheet(item: presentedSheet) { sheet in
            DestinationFactory.sheet(for: sheet, authentication: authentication, preferences: preferences,
                                     list: shoppingList, location: location)
        }
        .fullScreenCover(item: $appRouter.presentedCover, content: cover)
        .onChange(of: authentication.user) { _, user in
            if user == nil {
                appRouter.popToRoot(in: .home)
                appRouter.popToRoot(in: .catalog)
            }
        }
        .onChange(of: authentication.identity?.sessionID) {
            if case .profile? = appRouter.presentedSheet { appRouter.dismissSheet() }
        }
        .environment(\.preferredShoppingMode, preferences.mode)
        .environment(\.hasCompletedShoppingSurvey, preferences.hasCompletedSurvey)
        .environmentObject(appRouter)
        .modifier(CartAdditionNoticePresenter(hasAddedProduct: productSelection.hasAddedProductThisSession,
                                             openList: appRouter.openShoppingList))
    }

    @ViewBuilder
    private func cover(_ destination: AppRouter.Cover) -> some View {
        switch destination {
        case .survey(let accountID):
            NavigationStack {
                ShoppingSurveyView(preferences: preferences, accountID: accountID)
                    .navigationTitle(Texts.Survey.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        case .collection(let collection):
            let content = DestinationFactory.collection(collection, catalog: catalog, authentication: authentication,
                                                        storefrontTransition: storefrontTransition, shoppingList: shoppingList, location: location) {
                appRouter.presentedCover = nil
            }
            if reduceMotion { content }
            else { content.navigationTransition(.zoom(sourceID: collection, in: storefrontTransition)) }
        }
    }

    private func tabLabel(for tab: AppRouter.Tab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            switch tab {
            case .home: Image.Glyph.home
            case .shoppingList: Image.Glyph.list
            case .catalog: Image.Glyph.catalog
            case .search: Image.System.magnifyingGlass
            }
        }
    }

    private var selectedTab: Binding<AppRouter.Tab> {
        Binding(
            get: { appRouter.selectedTab },
            set: { appRouter.selectTab($0) }
        )
    }

    private func navigationStack(for tab: AppRouter.Tab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            DestinationFactory.view(for: tab.rootRoute, catalog: catalog, authentication: authentication,
                                    storefrontTransition: storefrontTransition, productSelection: productSelection, shoppingList: shoppingList, location: location)
                .navigationDestination(for: AppRouter.Route.self) { route in
                    DestinationFactory.view(for: route, catalog: catalog, authentication: authentication,
                                            storefrontTransition: storefrontTransition, productSelection: productSelection,
                                            shoppingList: shoppingList, location: location)
                }
        }
        .scaleEffect(contentScale, anchor: .top)
    }

    private func pathBinding(for tab: AppRouter.Tab) -> Binding<[AppRouter.Route]> {
        Binding(
            get: { appRouter.path(in: tab) },
            set: { appRouter.setPath($0, in: tab) }
        )
    }

    private var presentedSheet: Binding<AppRouter.Sheet?> {
        Binding(get: { appRouter.presentedSheet }, set: { _ in appRouter.dismissSheet() })
    }

    private enum Const {
        static let defaultContentScale: CGFloat = 1
    }
}

// MARK: - Preview

#Preview("Light") {
    AppRootView(catalog: PreviewCatalogRepository(), authentication: AuthenticationSession.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppRootView(catalog: PreviewCatalogRepository(), authentication: AuthenticationSession.preview())
        .preferredColorScheme(.dark)
}
