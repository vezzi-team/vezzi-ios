import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, catalog: any CatalogRepository) -> some View {
        Group {
            switch route {
            case .home:
                HomeView()
            case .shoppingList:
                ShoppingListView()
            case .stores:
                StoresView()
            case .search:
                SearchView(repository: catalog)
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
