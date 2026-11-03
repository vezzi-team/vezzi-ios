import Combine
import XCTest
@testable import vezzi_ios

@MainActor
final class SplashViewModelTests: XCTestCase {
    func testFinishingTwicePublishesDismissalOnlyOnce() {
        let viewModel = SplashViewModel()
        var states: [Bool] = []
        let observation = viewModel.$isPresented.sink { states.append($0) }
        defer { observation.cancel() }

        viewModel.finish()
        viewModel.finish()

        XCTAssertEqual(states, [true, false])
    }

    func testTimeoutDismissesSplashWithoutAnimationCompletion() async {
        let viewModel = SplashViewModel()
        await viewModel.finishAfterTimeout(timeout: .zero)
        XCTAssertFalse(viewModel.isPresented)
    }

    func testCancelledTimeoutDoesNotDismissSplash() async {
        let viewModel = SplashViewModel()
        let waiting = Task { await viewModel.finishAfterTimeout() }
        waiting.cancel()
        await waiting.value
        XCTAssertTrue(viewModel.isPresented)
    }
}
