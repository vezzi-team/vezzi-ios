import Combine
import Foundation

/// Manages the selected tab and a separate navigation history for each tab.
@MainActor
final class AppRouter: ObservableObject {
    @Published private(set) var selectedTab: Tab
    @Published private(set) var navigationPaths: [Tab: [Route]]
    @Published private(set) var presentedSheet: Sheet?
    @Published var presentedCover: Cover?
    let willOpenShoppingList = PassthroughSubject<Void, Never>()

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

    func presentAuthentication() {
        presentedSheet = .authentication
    }

    func openShoppingList() {
        willOpenShoppingList.send()
        presentedCover = nil
        dismissSheet()
        popToRoot(in: .shoppingList)
        selectedTab = .shoppingList
    }

    func presentProfile(_ sheet: ProfileSheet) {
        presentedSheet = .profile(sheet)
    }

    func dismissSheet() {
        presentedSheet = nil
    }

    func returnHomeFromSurvey() {
        popToRoot(in: .home)
        selectedTab = .home
        presentedCover = nil
    }

    func openProfileFromSurvey() {
        guard case .survey = presentedCover else { return }
        if path(in: selectedTab).last != .profile { push(.profile, in: selectedTab) }
        presentedCover = nil
    }

    enum Cover: Hashable, Identifiable {
        case collection(StorefrontCollection)
        case survey(accountID: UUID)
        var id: Self { self }
    }

    enum Sheet: Hashable, Identifiable {
        case authentication
        case profile(ProfileSheet)
        var id: Self { self }
    }
}

// MARK: - Tabs

extension AppRouter {
    enum Tab: CaseIterable, Hashable {
        case home
        case shoppingList
        case catalog
        case search

        var title: String {
            rootRoute.title
        }

        var rootRoute: Route {
            switch self {
            case .home: return .home
            case .shoppingList: return .shoppingList
            case .catalog: return .catalog
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
        case catalog
        case search
        case profile
        case profileData
        case motiDebug

        var title: String {
            switch self {
            case .home: return Texts.Tabbar.home
            case .shoppingList: return Texts.Tabbar.shoppingList
            case .catalog: return Texts.Tabbar.catalog
            case .search: return Texts.Tabbar.search
            case .profile: return Texts.Profile.Main.title
            case .profileData: return Texts.Profile.Main.personalDetails
            case .motiDebug: return Texts.Debug.Moti.title
            }
        }
    }
}
