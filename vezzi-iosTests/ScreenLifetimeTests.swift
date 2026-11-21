import SwiftUI
import XCTest
@testable import vezzi_ios

@MainActor
final class ScreenLifetimeTests: XCTestCase {
    func testSceneOverlaySurvivesTabChangesWithoutTakingFocusOrInterceptingOutsideTouches() async throws {
        let visible = expectation(description: "The overlay has an interactive region")
        let switched = expectation(description: "The second tab appeared")
        switched.assertForOverFulfill = false // Reattaching the stack also triggers onAppear.
        let barHidden = expectation(description: "The overlay moved to the top safe area")
        var expectedTopAfterHiding: CGFloat?
        var buttonFrame = CGRect.zero
        func root(presented: Bool, tab: Int = 0) -> some View {
            TabView(selection: .constant(tab)) {
                Tab(value: 0) { Color.clear } label: { Text("Catalog") }
                Tab(value: 1) { Color.clear.onAppear { switched.fulfill() } } label: { Text("List") }
            }
            .background {
                SceneOverlayWindow(isPresented: presented) { setRegion in
                    Button("Notice") {}
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            setRegion(Capsule().path(in: frame))
                            if buttonFrame.isEmpty && !frame.isEmpty { visible.fulfill() }
                            buttonFrame = frame
                            if let top = expectedTopAfterHiding, abs(frame.minY - top) < 1 {
                                expectedTopAfterHiding = nil
                                barHidden.fulfill()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        let host = UIHostingController(rootView: root(presented: false))
        let navigation = UINavigationController(rootViewController: host)
        let container = UIViewController()
        let main = try makeWindow(root: container)
        container.addChild(navigation)
        navigation.view.frame = container.view.bounds
        container.view.addSubview(navigation.view)
        navigation.didMove(toParent: container)
        defer { main.isHidden = true }
        let scene = try XCTUnwrap(main.windowScene)
        let originalWindows = Set(scene.windows.map(ObjectIdentifier.init))
        host.rootView = root(presented: true)
        await fulfillment(of: [visible], timeout: 5)

        weak var releasedWindow: UIWindow?
        weak var releasedHost: UIViewController?
        do {
            let overlay = try XCTUnwrap(scene.windows.first { !originalWindows.contains(ObjectIdentifier($0)) && $0.windowLevel > main.windowLevel })
            XCTAssertTrue(main.isKeyWindow)
            XCTAssertFalse(overlay.canBecomeKey)
            XCTAssertNil(overlay.hitTest(.zero, with: nil))
            let bar = navigation.navigationBar
            XCTAssertEqual(buttonFrame.minY, bar.convert(bar.bounds, to: main).maxY, accuracy: 1)
            let center = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
            XCTAssertNotNil(overlay.hitTest(center, with: nil))
            host.rootView = root(presented: true, tab: 1)
            await fulfillment(of: [switched], timeout: 5)
            XCTAssertTrue(scene.windows.contains { $0 === overlay && !$0.isHidden })
            XCTAssertNotNil(overlay.hitTest(center, with: nil))

            // Between tab stacks UIKit can briefly have no attached navigation controller.
            let attachedTop = buttonFrame.minY
            navigation.view.removeFromSuperview()
            await waitForTwoFrames(in: main)
            XCTAssertEqual(buttonFrame.minY, attachedTop, accuracy: 1)
            XCTAssertFalse(overlay.isHidden)
            XCTAssertNotNil(overlay.hitTest(center, with: nil))
            container.view.addSubview(navigation.view)

            expectedTopAfterHiding = main.safeAreaInsets.top
            navigation.setNavigationBarHidden(true, animated: false)
            await fulfillment(of: [barHidden], timeout: 5)
            releasedWindow = overlay
            releasedHost = overlay.rootViewController
        }
        host.rootView = root(presented: false, tab: 1)
        try await assertReleased { releasedWindow == nil && releasedHost == nil }
    }

    private func waitForTwoFrames(in window: UIWindow) async {
        let rendered = expectation(description: "UIKit committed the updated layout")
        let link = UIUpdateLink(view: window)
        var frames = 0
        link.addAction(to: .afterCATransactionCommit) { link, _ in
            frames += 1
            if frames == 2 {
                link.isEnabled = false
                rendered.fulfill()
            }
        }
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        defer { link.isEnabled = false }
        await fulfillment(of: [rendered], timeout: 5)
    }

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
