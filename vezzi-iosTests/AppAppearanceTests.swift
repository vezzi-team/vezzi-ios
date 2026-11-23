import UIKit
import XCTest
@testable import vezzi_ios

@MainActor
final class AppAppearanceTests: XCTestCase {
    func testLaunchStoryboardUsesPrimaryBackgroundAndOriginalWordmark() throws {
        let controller = try XCTUnwrap(UIStoryboard(name: "LaunchScreen", bundle: .main).instantiateInitialViewController())
        let view = try XCTUnwrap(controller.view)
        let logo = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first)
        let background = try XCTUnwrap(UIColor(named: "BackgroundPrimary"))

        for style: UIUserInterfaceStyle in [.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(view.backgroundColor?.resolvedColor(with: traits), background.resolvedColor(with: traits))
        }
        XCTAssertEqual(logo.image?.renderingMode, .alwaysOriginal)
    }

    func testExistingAndNewWindowsInheritTheScenePreferenceAndReturnToSystem() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let hasOverride = scene.traitOverrides.contains(UITraitUserInterfaceStyle.self)
        let previous = hasOverride ? scene.traitOverrides.userInterfaceStyle : nil
        defer {
            if let previous { scene.traitOverrides.userInterfaceStyle = previous }
            else { scene.traitOverrides.remove(UITraitUserInterfaceStyle.self) }
        }

        AppAppearance.system.apply(to: scene)
        let system = scene.traitCollection.userInterfaceStyle
        let existing = UIWindow(windowScene: scene)
        let anchor = AppSceneAppearance.Anchor()
        anchor.appearance = .dark
        existing.addSubview(anchor)
        XCTAssertEqual(existing.traitCollection.userInterfaceStyle, .dark)
        let presented = UIWindow(windowScene: scene)
        XCTAssertEqual(presented.traitCollection.userInterfaceStyle, .dark)
        anchor.appearance = .light
        XCTAssertEqual(existing.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(presented.traitCollection.userInterfaceStyle, .light)
        anchor.appearance = .system
        XCTAssertFalse(scene.traitOverrides.contains(UITraitUserInterfaceStyle.self))
        XCTAssertEqual(presented.traitCollection.userInterfaceStyle, system)
    }
}
