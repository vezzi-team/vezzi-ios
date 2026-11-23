import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    static let storageKey = "appearance.theme"

    func apply(to scene: UIWindowScene) {
        switch self {
        case .system: scene.traitOverrides.remove(UITraitUserInterfaceStyle.self)
        case .light: scene.traitOverrides.userInterfaceStyle = .light
        case .dark: scene.traitOverrides.userInterfaceStyle = .dark
        }
    }
}

/// Native search and the keyboard may use a different window in the same scene.
struct AppSceneAppearance: UIViewRepresentable {
    let appearance: AppAppearance

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.appearance = appearance
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        if anchor.appearance != appearance { anchor.appearance = appearance }
    }

    final class Anchor: UIView {
        var appearance: AppAppearance = .system {
            didSet { applyAppearance() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyAppearance()
        }

        private func applyAppearance() {
            if let scene = window?.windowScene { appearance.apply(to: scene) }
        }
    }
}
