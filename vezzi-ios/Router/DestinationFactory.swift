import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, catalog: any CatalogRepository,
                     authentication: AuthenticationSession, profileTransition: Namespace.ID) -> some View {
        Group {
            switch route {
            case .home:
                HomeView(authentication: authentication, profileTransition: profileTransition)
            case .shoppingList:
                ShoppingListView()
            case .stores:
                StoresView()
            case .search:
                SearchView(repository: catalog)
            case .profile:
                ProfileView(session: authentication)
            case .profileDetails(let destination):
                ProfileDetailView(destination: destination, session: authentication)
            case .motiDebug:
                MotiDebugView()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    static func sheet(for sheet: AppRouter.Sheet, authentication: AuthenticationSession) -> some View {
        switch sheet {
        case .authentication:
            LoginView(session: authentication)
        }
    }
}
