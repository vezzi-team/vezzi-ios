import SwiftUI

/// Composes the app's modules and owns state shared across tabs.
struct AppRootView: View {
    @StateObject private var appRouter: AppRouter
    // Keeps the same view model when switching tabs.
    @StateObject private var demoViewModel = DemoViewModel()

    init(initialTab: AppRouter.Tab = .shelf) {
        _appRouter = StateObject(wrappedValue: AppRouter(selectedTab: initialTab))
    }

    var body: some View {
        TabView(selection: selectedTab) {
            Tab(AppRouter.Tab.shelf.title,
                systemImage: AppRouter.Tab.shelf.systemImage,
                value: AppRouter.Tab.shelf) {
                navigationStack(for: .shelf)
            }

            Tab(AppRouter.Tab.map.title,
                systemImage: AppRouter.Tab.map.systemImage,
                value: AppRouter.Tab.map) {
                navigationStack(for: .map)
            }

            Tab(AppRouter.Tab.settings.title,
                systemImage: AppRouter.Tab.settings.systemImage,
                value: AppRouter.Tab.settings) {
                navigationStack(for: .settings)
            }

            // On iPhone, the search role presents search as a separate button.
            Tab(AppRouter.Tab.search.title,
                systemImage: AppRouter.Tab.search.systemImage,
                value: AppRouter.Tab.search,
                role: .search) {
                navigationStack(for: .search)
            }
        }
        .tint(.accentColor)
        .environmentObject(appRouter)
    }

    private var selectedTab: Binding<AppRouter.Tab> {
        Binding(
            get: { appRouter.selectedTab },
            set: { appRouter.selectTab($0) }
        )
    }

    private func navigationStack(for tab: AppRouter.Tab) -> some View {
        NavigationStack(path: pathBinding(for: tab)) {
            DestinationFactory.view(for: tab.rootRoute, demoViewModel: demoViewModel)
                .navigationDestination(for: AppRouter.Route.self) { route in
                    DestinationFactory.view(for: route, demoViewModel: demoViewModel)
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
