import Combine

/// Manages the selected tab and a separate navigation history for each tab.
@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var selectedTab: Tab
    @Published private(set) var navigationPaths: [Tab: [Route]]

    init(selectedTab: Tab = .home) {
        self.selectedTab = selectedTab
        navigationPaths = Dictionary(uniqueKeysWithValues: Tab.allCases.map { ($0, []) })
    }

    // Avoids an isolated-deinit runtime crash on older iOS 26 releases.
    // https://github.com/swiftlang/swift/issues/88036
    nonisolated deinit {}

    func selectTab(_ tab: Tab) {
        if selectedTab == tab {
            popToRoot(in: tab)
        } else {
            selectedTab = tab
        }
    }

    func path(in tab: Tab) -> [Route] {
        navigationPaths[tab, default: []]
    }

    /// Receives path updates from NavigationStack, including back swipe gestures.
    func setPath(_ path: [Route], in tab: Tab) {
        navigationPaths[tab] = path
    }

    func push(_ route: Route, in tab: Tab) {
        navigationPaths[tab, default: []].append(route)
    }

    func pop(in tab: Tab) {
        _ = navigationPaths[tab]?.popLast()
    }

    func popToRoot(in tab: Tab) {
        navigationPaths[tab] = []
    }
}

// MARK: - Tabs

extension AppRouter {
    enum Tab: CaseIterable, Hashable {
        case home
        case shoppingList
        case stores
        case search

        var title: String {
            rootRoute.title
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .shoppingList: return "checklist"
            case .stores: return "storefront"
            case .search: return "magnifyingglass"
            }
        }

        var rootRoute: Route {
            switch self {
            case .home: return .home
            case .shoppingList: return .shoppingList
            case .stores: return .stores
            case .search: return .search
            }
        }
    }
}

// MARK: - Routes

extension AppRouter {
    /// Routes store navigation data without holding views or view models.
    enum Route: Hashable {
        case home
        case shoppingList
        case stores
        case search

        var title: String {
            switch self {
            case .home: return Texts.Tabbar.home
            case .shoppingList: return Texts.Tabbar.shoppingList
            case .stores: return Texts.Tabbar.stores
            case .search: return Texts.Tabbar.search
            }
        }
    }
}
