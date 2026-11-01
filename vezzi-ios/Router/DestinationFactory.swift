import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, demoViewModel: DemoViewModel) -> some View {
        Group {
            switch route {
            case .shelf:
                DemoView(viewModel: demoViewModel)
            case .map:
                MapView()
            case .settings:
                SettingsView()
            case .search:
                SearchView()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
