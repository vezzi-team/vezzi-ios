import Foundation

nonisolated protocol AuthenticationService: Sendable {
    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant
    func commit(_ grant: AuthenticationGrant) async throws -> AuthenticatedUser
    func discard(_ grant: AuthenticationGrant) async throws
    func cachedIdentity() async throws -> AuthenticationIdentity?
    func currentUser() async throws -> AuthenticatedUser
    func signOut() async throws
}
