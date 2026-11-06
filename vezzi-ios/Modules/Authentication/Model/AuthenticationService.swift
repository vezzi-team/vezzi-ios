import Foundation

nonisolated struct AuthenticatedUser: Equatable, Sendable {
    let email: String
}

nonisolated enum AuthenticationIntent: Equatable, Sendable {
    case signIn
    case register
}

/// Replace this adapter when the backend's authentication contract is available.
@MainActor
protocol AuthenticationService {
    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticatedUser
}

struct MockAuthenticationService: AuthenticationService {
    nonisolated init() {}

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticatedUser {
        try await Task.sleep(for: .seconds(1))
        try Task.checkCancellation()
        return AuthenticatedUser(email: email)
    }
}
