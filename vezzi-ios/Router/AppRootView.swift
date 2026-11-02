import SwiftUI

/// Composes the app's modules and owns state shared across tabs.
struct AppRootView: View {
    @StateObject private var appRouter: AppRouter

    init(initialTab: AppRouter.Tab = .home) {
        _appRouter = StateObject(wrappedValue: AppRouter(selectedTab: initialTab))
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab(AppRouter.Tab.home.title,
                systemImage: AppRouter.Tab.home.systemImage,
                value: AppRouter.Tab.home) {
                navigationStack(for: .home)
            }

            Tab(AppRouter.Tab.shoppingList.title,
                systemImage: AppRouter.Tab.shoppingList.systemImage,
                value: AppRouter.Tab.shoppingList) {
                navigationStack(for: .shoppingList)
            }

            Tab(AppRouter.Tab.stores.title,
                systemImage: AppRouter.Tab.stores.systemImage,
                value: AppRouter.Tab.stores) {
                navigationStack(for: .stores)
            }

            // Keeps search separate from the other tabs on iPhone.
            Tab(AppRouter.Tab.search.title,
                systemImage: AppRouter.Tab.search.systemImage,
                value: AppRouter.Tab.search,
                role: searchTabRole) {
                navigationStack(for: .search)
            }
        }
        .tint(.accentColor)
        .environmentObject(appRouter)
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
            DestinationFactory.view(for: tab.rootRoute)
                .navigationDestination(for: AppRouter.Route.self) { route in
                    DestinationFactory.view(for: route)
                }
        }
    }

    private func pathBinding(for tab: AppRouter.Tab) -> Binding<[AppRouter.Route]> {
        Binding(
            get: { appRouter.path(in: tab) },
            set: { appRouter.setPath($0, in: tab) }
        )
    }
}

// MARK: - Preview

#Preview("Light") {
    AppRootView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppRootView()
        .preferredColorScheme(.dark)
}
