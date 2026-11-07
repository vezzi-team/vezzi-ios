import Foundation

nonisolated protocol AuthenticationService: Sendable {
    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant
    func commit(_ grant: AuthenticationGrant) async throws -> AuthenticatedUser
    func discard(_ grant: AuthenticationGrant) async throws
    func cachedUser() async throws -> AuthenticatedUser?
    func currentUser() async throws -> AuthenticatedUser
    func signOut() async throws
}
