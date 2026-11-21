import Combine
import Foundation

/// Coordinates account actions for the identity that opened the data screen.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var showsSignOutConfirmation = false
    @Published var showsSignOutError = false
    @Published private(set) var isSigningOut = false

    private let session: AuthenticationSession
    private let sessionID: UUID?

    init(session: AuthenticationSession) {
        self.session = session
        sessionID = session.identity?.sessionID
    }

    nonisolated deinit {}

    func signOut() async {
        guard !isSigningOut, session.identity?.sessionID == sessionID else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do { try await session.signOut() }
        catch { showsSignOutError = true }
    }
}
