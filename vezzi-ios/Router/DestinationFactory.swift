import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, catalog: any CatalogRepository,
                     authentication: AuthenticationSession, profileTransition: Namespace.ID,
                     productSelection: ProductSelection) -> some View {
        Group {
            switch route {
            case .home:
                HomeView(authentication: authentication, profileTransition: profileTransition, selection: productSelection)
            case .shoppingList:
                ShoppingListView()
            case .stores:
                StoresView()
            case .search:
                SearchView(repository: catalog, selection: productSelection, stores: SearchMockData.stores,
                           groupOrder: SearchMockData.groupOrder)
            case .profile:
                ProfileView(session: authentication)
            case .profileDetails(let destination):
                ProfileDetailView(destination: destination, session: authentication)
            case .motiDebug:
                MotiDebugView()
            }
        }
        .navigationTitle(route == .search ? "" : route.title)
        .navigationBarTitleDisplayMode(route == .search ? .inline : .large)
    }

    @ViewBuilder
    static func sheet(for sheet: AppRouter.Sheet, authentication: AuthenticationSession) -> some View {
        switch sheet {
        case .authentication:
            LoginView(session: authentication)
        }
    }
}
