import Lottie
import SwiftUI

struct SplashView: View {
    private let onFinished: () -> Void

    init(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.Background.primary
                    .ignoresSafeArea()

                LottieView(animation: Const.animation)
                    .playing(loopMode: .playOnce)
                    .animationDidFinish { completed in
                        if completed { onFinished() }
                    }
                    .backgroundBehavior(.pauseAndRestore)
                    .resizable()
                    .frame(width: mascotSize(in: geometry.size), height: mascotSize(in: geometry.size))
                    .offset(y: -Const.mascotVerticalOffset)
                    .accessibilityHidden(true)

                VStack {
                    Spacer()
                    Image.Brand.wordmark
                        .resizable()
                        .scaledToFit()
                        .frame(width: Const.wordmarkWidth)
                        .padding(.bottom, Const.wordmarkBottomPadding)
                        .accessibilityLabel(Texts.AppInfo.title)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if Const.animation == nil { onFinished() }
        }
    }

    private func mascotSize(in size: CGSize) -> CGFloat {
        min(size.width * Const.mascotWidthRatio, size.height * Const.mascotHeightRatio, Const.mascotMaximumSize)
    }

    private enum Const {
        static let animation = LottieAnimation.named("MotiSplash")
        static let mascotMaximumSize: CGFloat = 340
        static let mascotWidthRatio: CGFloat = 0.88
        static let mascotHeightRatio: CGFloat = 0.65
        static let mascotVerticalOffset: CGFloat = 16
        // Match these dimensions and the safe-area inset in LaunchScreen.storyboard.
        static let wordmarkWidth: CGFloat = 160
        static let wordmarkBottomPadding: CGFloat = 32
    }
}

#Preview("Light") {
    SplashView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SplashView()
        .preferredColorScheme(.dark)
}
