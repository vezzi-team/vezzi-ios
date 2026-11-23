import SwiftUI

/// Presents first-launch onboarding or the home tabs beneath the brief splash.
struct AppLaunchView: View {
    @StateObject private var splash = SplashViewModel()
    @AppStorage("onboarding.completed") private var completedOnboarding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let catalog: any CatalogRepository
    let authentication: AuthenticationSession
    var shoppingList: ShoppingListRepository = ShoppingListRepository()
    var location: any DeviceLocating = DeviceLocationService()

    private var showsSplash: Bool { splash.isPresented && !reduceMotion }

    private var animatesReveal: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        ZStack {
            launchContent
                .allowsHitTesting(!showsSplash)
                .accessibilityHidden(showsSplash)

            if showsSplash {
                SplashView(onFinished: splash.finish)
                    .transition(.opacity.animation(
                        animatesReveal ? .easeOut(duration: Const.dismissDuration) : nil
                    ))
                    .zIndex(Const.splashZIndex)
            }
        }
        .animation(
            animatesReveal ? .spring(duration: Const.contentRevealDuration) : nil,
            value: showsSplash
        )
        .transaction(value: showsSplash) { transaction in
            if !animatesReveal {
                transaction.disablesAnimations = true
            }
        }
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

    private var launchContent: some View {
        ZStack {
            if completedOnboarding {
                AppRootView(catalog: catalog, authentication: authentication, shoppingList: shoppingList,
                            location: location, contentScale: showsSplash ? Const.initialContentScale : Const.restingContentScale)
                    .transition(.identity)
            } else {
                OnboardingView(authentication: authentication) { completedOnboarding = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(animatesReveal ? .easeInOut(duration: Const.onboardingDismissDuration) : nil,
                   value: completedOnboarding)
    }

    private enum Const {
        static let splashZIndex: Double = 1
        static let initialContentScale: CGFloat = 1.35
        static let restingContentScale: CGFloat = 1
        static let contentRevealDuration: TimeInterval = 0.4
        static let onboardingDismissDuration: TimeInterval = 0.4
        static let dismissDuration: TimeInterval = 0.12
    }
}

#Preview("Launch") {
    AppLaunchView(catalog: PreviewCatalogRepository(), authentication: AuthenticationSession.preview())
}

#Preview("Launch — dark") {
    AppLaunchView(catalog: PreviewCatalogRepository(), authentication: AuthenticationSession.preview())
        .preferredColorScheme(.dark)
}
