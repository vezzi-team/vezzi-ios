import SwiftUI

/// Maps each route to the corresponding module's screen.
enum DestinationFactory {
    static func view(for route: AppRouter.Route, catalog: any CatalogRepository,
                     authentication: AuthenticationSession, storefrontTransition: Namespace.ID,
                     productSelection: ProductSelection, shoppingList: ShoppingListRepository, location: any DeviceLocating) -> some View {
        func storefront(_ page: StorefrontPage) -> StorefrontScreen {
            StorefrontScreen(page: page, repository: catalog, authentication: authentication,
                             storefrontTransition: storefrontTransition, list: shoppingList, location: location)
        }

        return Group {
            switch route {
            case .home:
                storefront(.home)
            case .catalog:
                storefront(.catalog)
            case .shoppingList:
                ShoppingListView(catalog: catalog, list: shoppingList, location: location)
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

    static func collection(_ collection: StorefrontCollection, catalog: any CatalogRepository, authentication: AuthenticationSession,
                           storefrontTransition: Namespace.ID, shoppingList: ShoppingListRepository,
                           location: any DeviceLocating, close: @escaping () -> Void) -> some View {
        NavigationStack {
            StorefrontScreen(page: .collection(collection), repository: catalog, authentication: authentication,
                             storefrontTransition: storefrontTransition, list: shoppingList, location: location)
                .navigationTitle(collection.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close, action: close)
                            .tint(Color.Label.primary)
                            .accessibilityIdentifier(AccessibilityID.closeCollection(collection))
                    }
                }
        }
    }
}
