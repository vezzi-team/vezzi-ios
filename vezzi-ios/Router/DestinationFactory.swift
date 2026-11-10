import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, catalog: any CatalogRepository,
                     authentication: AuthenticationSession, profileTransition: Namespace.ID,
                     productSelection: ProductSelection, shoppingList: ShoppingListRepository) -> some View {
        Group {
            switch route {
            case .home:
                HomeView(repository: catalog, authentication: authentication, profileTransition: profileTransition, selection: productSelection)
            case .shoppingList:
                ShoppingListView(catalog: catalog, list: shoppingList)
            case .stores:
                StoresView()
            case .search:
                SearchView(repository: catalog, selection: productSelection)
            case .profile:
                ProfileView(session: authentication)
            case .profileDetails(let destination):
                ProfileDetailView(destination: destination, session: authentication)
            case .motiDebug:
                MotiDebugView()
            }
        }
        .navigationTitle(route == .search ? "" : route == .shoppingList ? Texts.ShoppingList.title : route.title)
        .toolbarTitleDisplayMode(route == .search ? .inline : route == .shoppingList ? .inlineLarge : .large)
    }

    @ViewBuilder
    static func sheet(for sheet: AppRouter.Sheet, authentication: AuthenticationSession) -> some View {
        switch sheet {
        case .authentication:
            LoginView(session: authentication)
        }
    }
}
