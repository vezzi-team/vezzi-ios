import Foundation

/// Explicitly injected by previews and tests; never used by the production composition root.
actor MockAuthenticationService: AuthenticationService {
    private var identity: AuthenticationIdentity?

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        try await Task.sleep(for: .seconds(1))
        let user = AuthenticatedUser(id: UUID(), email: email, role: "user", createdAt: Date())
        return AuthenticationGrant(generation: UUID(), session: StoredAuthentication(
            user: user, tokens: AuthenticationTokens(accessToken: "preview", refreshToken: "preview", expiresIn: 1_800)
        ))
    }

    func commit(_ grant: AuthenticationGrant) throws -> AuthenticatedUser {
        try Task.checkCancellation()
        identity = AuthenticationIdentity(sessionID: grant.session.id, user: grant.session.user)
        return grant.session.user
    }

    func discard(_ grant: AuthenticationGrant) {
        if identity?.sessionID == grant.session.id { identity = nil }
    }

    func cachedIdentity() -> AuthenticationIdentity? { identity }

    func currentUser() throws -> AuthenticatedUser {
        guard let user = identity?.user else { throw AuthenticationFailure.sessionExpired }
        return user
    }

    func signOut() { identity = nil }
}
