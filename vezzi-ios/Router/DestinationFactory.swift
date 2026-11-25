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
                ShoppingListView(catalog: catalog, list: shoppingList, location: location,
                                 isRestoringAccount: authentication.isRestoring)
            case .search:
                SearchView(repository: catalog, selection: productSelection)
            case .profile:
                ProfileView(session: authentication, list: shoppingList)
            case .profileData:
                ProfileDataView(session: authentication)
            case .motiDebug:
                MotiDebugView()
            }
        }
        .navigationTitle(route == .search ? "" : route == .shoppingList ? Texts.ShoppingList.title : route.title)
        .toolbarTitleDisplayMode(titleMode(for: route))
    }

    @ViewBuilder
    static func sheet(for sheet: AppRouter.Sheet, authentication: AuthenticationSession, preferences: ShoppingPreferences,
                      list: ShoppingListRepository, location: any DeviceLocating) -> some View {
        switch sheet {
        case .authentication:
            LoginView(session: authentication)
        case .profile(let destination):
            ProfileSheetHost(destination: destination, preferences: preferences, list: list, location: location)
        }
    }

    private static func titleMode(for route: AppRouter.Route) -> ToolbarTitleDisplayMode {
        switch route {
        case .profile, .profileData, .search: return .inline
        case .shoppingList: return .inlineLarge
        default: return .large
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

/// Sheet navigation is isolated from the tab's typed history.
private struct ProfileSheetHost: View {
    let destination: ProfileSheet
    let preferences: ShoppingPreferences
    let list: ShoppingListRepository
    let location: any DeviceLocating

    var body: some View {
        NavigationStack {
            switch destination {
            case .shopping: ShoppingModeView(preferences: preferences)
            case .address: ProfileAddressView(list: list, location: location)
            case .settings: ProfileSettingsView()
            case .about: AboutView()
            }
        }
        .presentationDragIndicator(.visible)
    }
}
