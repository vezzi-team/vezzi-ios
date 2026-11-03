import SwiftUI

/// Keeps navigation and cache preparation alive underneath the brief launch overlay.
struct AppLaunchView: View {
    @StateObject private var splash = SplashViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let catalog: any CatalogRepository

    private var showsSplash: Bool { splash.isPresented && !reduceMotion }

    var body: some View {
        ZStack {
            AppRootView(catalog: catalog)
                .allowsHitTesting(!showsSplash)
                .accessibilityHidden(showsSplash)

            if showsSplash {
                SplashView(onFinished: splash.finish)
                    .transition(.opacity)
                    .zIndex(Const.splashZIndex)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Const.dismissDuration), value: showsSplash)
        .task(id: showsSplash) {
            if showsSplash { await splash.finishAfterTimeout() }
        }
        .onChange(of: reduceMotion, initial: true) { _, reduced in
            if reduced { splash.finish() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to this scene must not resume an obsolete launch animation.
            if phase == .background { splash.finish() }
        }
    }

    private enum Const {
        static let splashZIndex: Double = 1
        static let dismissDuration: TimeInterval = 0.16
    }
}

#Preview("Launch") {
    AppLaunchView(catalog: PreviewCatalogRepository())
}

#Preview("Launch — dark") {
    AppLaunchView(catalog: PreviewCatalogRepository())
        .preferredColorScheme(.dark)
}
