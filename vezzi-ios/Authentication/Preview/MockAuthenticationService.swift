import Foundation

/// Explicitly injected by previews and tests; never used by the production composition root.
actor MockAuthenticationService: AuthenticationService {
    private var user: AuthenticatedUser?

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        try await Task.sleep(for: .seconds(1))
        let user = AuthenticatedUser(id: UUID(), email: email, role: "user", createdAt: Date())
        return AuthenticationGrant(generation: UUID(), session: StoredAuthentication(
            user: user, tokens: AuthenticationTokens(accessToken: "preview", refreshToken: "preview", expiresIn: 1_800)
        ))
    }

    func commit(_ grant: AuthenticationGrant) throws -> AuthenticatedUser {
        try Task.checkCancellation()
        user = grant.session.user
        return grant.session.user
    }

    func discard(_ grant: AuthenticationGrant) {
        if user?.id == grant.session.user.id { user = nil }
    }

    func cachedUser() -> AuthenticatedUser? { user }

    func currentUser() throws -> AuthenticatedUser {
        guard let user else { throw AuthenticationFailure.sessionExpired }
        return user
    }

    func signOut() { user = nil }
}
