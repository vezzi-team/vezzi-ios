import Combine

/// Temporary in-memory account state. No credentials or authentication tokens are persisted.
@MainActor
final class AuthenticationSession: ObservableObject {
    @Published private(set) var user: AuthenticatedUser?
    @Published var preferences = ProfilePreferences()

    let service: any AuthenticationService

    init(service: any AuthenticationService = MockAuthenticationService()) {
        self.service = service
    }

    nonisolated deinit {}

    func signIn(as user: AuthenticatedUser) {
        preferences = ProfilePreferences()
        self.user = user
    }

    func signOut() {
        user = nil
        preferences = ProfilePreferences()
    }
}
