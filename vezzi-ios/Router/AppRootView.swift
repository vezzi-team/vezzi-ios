import SwiftUI

/// Composes the app's modules and owns state shared across tabs.
struct AppRootView: View {
    @StateObject private var appRouter: AppRouter
    @StateObject private var productSelection = ProductSelection()
    @ObservedObject private var authentication: AuthenticationSession
    @Namespace private var profileTransition
    private let catalog: any CatalogRepository
    private let contentScale: CGFloat

    init(
        catalog: any CatalogRepository,
        authentication: AuthenticationSession,
        initialTab: AppRouter.Tab = .home,
        contentScale: CGFloat = Const.defaultContentScale
    ) {
        self.catalog = catalog
        self.authentication = authentication
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

            Tab(value: AppRouter.Tab.stores) {
                navigationStack(for: .stores)
            } label: {
                tabLabel(for: .stores)
            }

            Tab(value: AppRouter.Tab.search, role: .search) {
                navigationStack(for: .search)
            } label: {
                tabLabel(for: .search)
            }
        }
        // Also gives the search tab its detached appearance on iOS 27.
        .tabViewSearchActivation(.searchTabSelection)
        .tint(.accentColor)
        .environmentObject(appRouter)
        .sensoryFeedback(.selection, trigger: productSelection.quantities)
        .sheet(item: presentedSheet) { sheet in
            DestinationFactory.sheet(for: sheet, authentication: authentication)
                .navigationTransition(.zoom(sourceID: sheet, in: profileTransition))
        }
        .onChange(of: authentication.user) { _, user in
            if user == nil { appRouter.popToRoot(in: .home) }
        }
    }

    private func tabLabel(for tab: AppRouter.Tab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            switch tab {
            case .home: Image.System.house
            case .shoppingList: Image.System.checklist
            case .stores: Image.System.storefront
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
                                    profileTransition: profileTransition, productSelection: productSelection)
                .navigationDestination(for: AppRouter.Route.self) { route in
                    DestinationFactory.view(for: route, catalog: catalog, authentication: authentication,
                                            profileTransition: profileTransition, productSelection: productSelection)
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
