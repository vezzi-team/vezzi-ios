import Combine

/// Manages the selected tab and a separate navigation history for each tab.
@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var selectedTab: Tab
    @Published private(set) var navigationPaths: [Tab: [Route]]

    init(selectedTab: Tab = .shelf) {
        self.selectedTab = selectedTab
        navigationPaths = Dictionary(uniqueKeysWithValues: Tab.allCases.map { ($0, []) })
    }

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
        case shelf
        case map
        case settings
        case search

        var title: String {
            rootRoute.title
        }

        var systemImage: String {
            switch self {
            case .shelf: return "square.stack.3d.up"
            case .map: return "map"
            case .settings: return "gearshape"
            case .search: return "magnifyingglass"
            }
        }

        var rootRoute: Route {
            switch self {
            case .shelf: return .shelf
            case .map: return .map
            case .settings: return .settings
            case .search: return .search
            }
        }
    }
}

// MARK: - Routes

extension AppRouter {
    /// Routes store navigation data without holding views or view models.
    enum Route: Hashable {
        case shelf
        case map
        case settings
        case search

        var title: String {
            switch self {
            case .shelf: return Texts.Tabbar.shelf
            case .map: return Texts.Tabbar.map
            case .settings: return Texts.Tabbar.settings
            case .search: return Texts.Tabbar.search
            }
        }
    }
}
