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
        .toolbarTitleDisplayMode(titleMode(for: route))
    }

    @ViewBuilder
    static func sheet(for sheet: AppRouter.Sheet, authentication: AuthenticationSession) -> some View {
        switch sheet {
        case .authentication:
            LoginView(session: authentication)
        case .profile(let destination):
            ProfileSheetHost(destination: destination, session: authentication)
        }
    }

    private static func titleMode(for route: AppRouter.Route) -> ToolbarTitleDisplayMode {
        switch route {
        case .profile, .profileDetails, .search: return .inline
        case .shoppingList: return .inlineLarge
        default: return .large
        }
    }
}

/// Sheet navigation is isolated from the tab's typed history.
private struct ProfileSheetHost: View {
    let destination: ProfileSheet
    @ObservedObject var session: AuthenticationSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Group {
                switch destination {
                case .shopping: ShoppingModeView(session: session)
                case .addresses: AddressesView(session: session)
                case .notifications: NotificationsView(session: session)
                case .about: AboutView()
                }
            }
        }
        .id(session.identity?.sessionID)
        .presentationDetents(destination.isCompact && !dynamicTypeSize.isAccessibilitySize
                             ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }
}
