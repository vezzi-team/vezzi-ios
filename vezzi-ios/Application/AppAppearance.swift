import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    static let storageKey = "appearance.theme"

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Apply the preference to the scene window, including native sheets and full-screen covers.
struct AppWindowAppearance: UIViewRepresentable {
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.style = appearance.interfaceStyle
        anchor.apply()
    }

    final class Anchor: UIView {
        var style: UIUserInterfaceStyle = .unspecified

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let window, window.overrideUserInterfaceStyle != style else { return }
            window.overrideUserInterfaceStyle = style
        }
    }
}
