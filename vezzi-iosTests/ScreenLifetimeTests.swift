import SwiftUI
import XCTest
@testable import vezzi_ios

@MainActor
final class ScreenLifetimeTests: XCTestCase {
    func testDismissingAddressSearchReleasesItsService() async throws {
        let presenter = UIViewController()
        let window = try makeWindow(root: presenter)
        defer { window.isHidden = true }

        weak var retainedService: MapKitAddressSearch?
        do {
            let service = MapKitAddressSearch()
            retainedService = service
            let controller = UIHostingController(rootView: AddressSearchView(near: .previewOrigin, service: service) { _ in })
            await withCheckedContinuation { continuation in
                presenter.present(controller, animated: true) { continuation.resume() }
            }
            await withCheckedContinuation { continuation in
                controller.dismiss(animated: true) { continuation.resume() }
            }
        }

        try await assertReleased { retainedService == nil }
    }

    func testRemovingShoppingListReleasesItsRepository() async throws {
        let appeared = expectation(description: "Shopping list appeared")
        let catalog = PreviewCatalogRepository()
        let router = AppRouter()
        func root(list: ShoppingListRepository?) -> some View {
            NavigationStack {
                if let list {
                    ShoppingListView(catalog: catalog, list: list)
                        .onAppear { appeared.fulfill() }
                } else {
                    Color.clear
                }
            }
            .environmentObject(router)
        }

        let host = UIHostingController(rootView: root(list: nil))
        let window = try makeWindow(root: host)
        defer { window.isHidden = true }
        weak var retainedList: ShoppingListRepository?
        do {
            let list = ShoppingListRepository()
            retainedList = list
            host.rootView = root(list: list)
        }
        await fulfillment(of: [appeared], timeout: 5)
        host.rootView = root(list: nil)
        try await assertReleased { retainedList == nil }
    }

    private func makeWindow(root: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        return window
    }

    private func assertReleased(file: StaticString = #filePath, line: UInt = #line,
                                _ isReleased: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while !isReleased(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(isReleased(), "The screen still retains its dependency", file: file, line: line)
    }
}
