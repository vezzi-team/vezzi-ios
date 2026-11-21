import SwiftUI

/// Hosts one overlay above the presenting scene's sheets, leaving its key window and keyboard focus intact.
struct SceneOverlayWindow<Overlay: View>: UIViewRepresentable {
    let isPresented: Bool
    @ViewBuilder let overlay: (@escaping (Path) -> Void) -> Overlay

    func makeUIView(context: Context) -> Anchor { Anchor() }

    func updateUIView(_ anchor: Anchor, context: Context) {
        guard isPresented else {
            anchor.close()
            return
        }
        guard anchor.overlayWindow == nil else { return }
        anchor.makeController = { window in
            let host = UIHostingController(rootView: overlay { [weak window] in window?.interactiveRegion = $0 })
            host.view.backgroundColor = .clear
            return host
        }
        anchor.presentIfReady()
    }

    static func dismantleUIView(_ anchor: Anchor, coordinator: ()) { anchor.close() }

    final class Anchor: UIView {
        private weak var sourceWindow: UIWindow?
        private var layoutUpdates: UIUpdateLink?
        fileprivate var overlayWindow: OverlayWindow?
        fileprivate var makeController: ((OverlayWindow) -> UIViewController)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // A full-screen cover can temporarily detach the presenting view.
            if let window {
                sourceWindow = window
                presentIfReady()
            }
        }

        fileprivate func presentIfReady() {
            guard overlayWindow == nil, let sourceWindow, let scene = sourceWindow.windowScene, let makeController else { return }
            let window = OverlayWindow(windowScene: scene)
            window.windowLevel = .normal + 1
            window.backgroundColor = .clear
            window.rootViewController = makeController(window)
            overlayWindow = window
            self.makeController = nil
            window.updateTopInset(from: sourceWindow)
            window.isHidden = false
            // Follow tab, sheet and bar geometry only while UIKit is already producing frames.
            let updates = UIUpdateLink(view: sourceWindow)
            updates.addAction(to: .beforeCATransactionCommit) { [weak window, weak sourceWindow] _, _ in
                if let sourceWindow { window?.updateTopInset(from: sourceWindow) }
            }
            layoutUpdates = updates
            updates.isEnabled = true
        }

        fileprivate func close() {
            layoutUpdates?.isEnabled = false
            layoutUpdates = nil
            makeController = nil
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
        }
    }
}

private final class OverlayWindow: UIWindow {
    var interactiveRegion = Path()
    override var canBecomeKey: Bool { false }

    func updateTopInset(from source: UIWindow) {
        // UIKit briefly detaches both bars during a tab switch. Keep the last measured inset then.
        guard let host = rootViewController, let root = source.rootViewController,
              let nav = navigationController(in: root, window: source),
              nav.viewIfLoaded?.window === source else { return }
        let inset: CGFloat
        if nav.isNavigationBarHidden {
            inset = 0
        } else {
            let bar = nav.navigationBar
            guard bar.window === source, !bar.isHidden, !bar.bounds.isEmpty else { return }
            let bottom = bar.convert(bar.bounds, to: source).maxY
            guard bottom > source.safeAreaInsets.top else { return }
            inset = bottom - source.safeAreaInsets.top
        }
        if host.additionalSafeAreaInsets.top != inset { host.additionalSafeAreaInsets.top = inset }
    }

    private func navigationController(in controller: UIViewController, window: UIWindow) -> UINavigationController? {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            // A partial-height panel leaves the navigation bar of the presenting screen at the top.
            let detent = presented.sheetPresentationController?.selectedDetentIdentifier
            if detent == nil || detent == .large {
                return navigationController(in: presented, window: window)
            }
        }
        if let tabs = controller as? UITabBarController {
            guard tabs.transitionCoordinator == nil, let selected = tabs.selectedViewController else { return nil }
            return navigationController(in: selected, window: window)
        }
        if let nav = controller as? UINavigationController { return nav }
        for child in controller.children.reversed() where child.viewIfLoaded?.window === window {
            if let nav = navigationController(in: child, window: window) { return nav }
        }
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveRegion.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
