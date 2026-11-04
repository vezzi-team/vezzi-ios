import SwiftUI

/// Composes the app's modules and owns state shared across tabs.
struct AppRootView: View {
    @StateObject private var appRouter: AppRouter
    private let catalog: any CatalogRepository
    private let contentScale: CGFloat

    init(
        catalog: any CatalogRepository,
        initialTab: AppRouter.Tab = .home,
        contentScale: CGFloat = Const.defaultContentScale
    ) {
        self.catalog = catalog
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

            // Keeps search separate from the other tabs on iPhone.
            Tab(value: AppRouter.Tab.search, role: searchTabRole) {
                navigationStack(for: .search)
            } label: {
                tabLabel(for: .search)
            }
        }
        .tint(.accentColor)
        .environmentObject(appRouter)
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

    private var searchTabRole: TabRole {
        if #available(iOS 27.0, *) {
            return .prominent
        } else {
            return .search
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
            DestinationFactory.view(for: tab.rootRoute, catalog: catalog)
                .navigationDestination(for: AppRouter.Route.self) { route in
                    DestinationFactory.view(for: route, catalog: catalog)
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

    private enum Const {
        static let defaultContentScale: CGFloat = 1
    }
}

// MARK: - Preview

#Preview("Light") {
    AppRootView(catalog: PreviewCatalogRepository())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppRootView(catalog: PreviewCatalogRepository())
        .preferredColorScheme(.dark)
}
