import Combine
import Foundation

@MainActor
final class SplashViewModel: ObservableObject {
    @Published private(set) var isPresented = true

    nonisolated deinit {}

    func finish() {
        guard isPresented else { return }
        isPresented = false
    }

    /// A missing completion callback must never leave the application covered.
    func finishAfterTimeout(timeout: Duration = .milliseconds(1600)) async {
        do {
            try await Task.sleep(for: timeout)
        } catch {
            return
        }
        finish()
    }
}
