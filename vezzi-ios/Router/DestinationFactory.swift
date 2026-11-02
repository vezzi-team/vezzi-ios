import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route) -> some View {
        Group {
            switch route {
            case .home:
                HomeView()
            case .shoppingList:
                ShoppingListView()
            case .stores:
                StoresView()
            case .search:
                SearchView()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
