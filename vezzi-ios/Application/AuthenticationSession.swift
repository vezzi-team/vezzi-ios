import Combine
import Foundation

/// Main-actor presentation state. The service owns credentials, storage and token rotation.
@MainActor
final class AuthenticationSession: ObservableObject {
    @Published private(set) var identity: AuthenticationIdentity?
    var user: AuthenticatedUser? { identity?.user }
    @Published private(set) var isRestoring: Bool
    @Published private(set) var isVerifying = false
    @Published private(set) var isSigningOut = false
    @Published private(set) var lastError: AuthenticationFailure?
    var requiresSignIn: Bool { identity == nil && sessionExpired }
    @Published private var sessionExpired: Bool {
        didSet {
            if oldValue != sessionExpired { defaults?.set(sessionExpired, forKey: Self.expirationKey) }
        }
    }

    private static let expirationKey = "authentication.sessionExpired"
    private let service: any AuthenticationService
    private let defaults: UserDefaults?
    private var revision = UUID()
    private var hasRestored = false
    private var activeSignIn: UUID?
    private var pendingGrant: AuthenticationGrant?
    private var pendingDiscard: Task<Void, Never>?

    init(service: any AuthenticationService, startsRestoring: Bool = false, defaults: UserDefaults? = nil) {
        self.service = service
        self.defaults = defaults
        sessionExpired = defaults?.bool(forKey: Self.expirationKey) ?? false
        isRestoring = startsRestoring
    }

    nonisolated deinit {}

    static func preview() -> AuthenticationSession {
        AuthenticationSession(service: MockAuthenticationService())
    }

    func restore(afterRejectionOf sessionID: UUID) async {
        guard identity?.sessionID == sessionID else { return }
        // An in-flight profile lookup may still return a result for the rejected session.
        if isVerifying {
            revision = UUID()
            isVerifying = false
        }
        await restore(force: true)
    }

    func restore(force: Bool = false) async {
        guard !isVerifying, !isSigningOut, activeSignIn == nil, force || !hasRestored else { return }
        let revision = revision
        isVerifying = true
        isRestoring = user == nil && !hasRestored
        defer {
            if self.revision == revision {
                isVerifying = false
                isRestoring = false
            }
        }
        do {
            // A foreground restore must not read a grant whose cancellation is still reaching the actor.
            await pendingDiscard?.value
            try Task.checkCancellation()
            guard self.revision == revision else { return }
            let cached = try await service.cachedIdentity()
            try Task.checkCancellation()
            guard self.revision == revision else { return }
            hasRestored = true
            isRestoring = false
            lastError = nil
            guard let cached else {
                // An authorized request can invalidate credentials before restoration reads them.
                if identity != nil {
                    sessionExpired = true
                    lastError = .sessionExpired
                }
                identity = nil
                return
            }
            identity = cached
            let verified = try await service.currentUser()
            try Task.checkCancellation()
            guard self.revision == revision else { return }
            identity = AuthenticationIdentity(sessionID: cached.sessionID, user: verified)
            sessionExpired = false
        } catch is CancellationError {
            // Cancellation is not evidence that the saved session is invalid.
        } catch {
            guard self.revision == revision else { return }
            let failure = AuthenticationFailure.from(error)
            lastError = failure
            if failure.invalidatesSession {
                sessionExpired = true
                identity = nil
            }
        }
    }

    func signIn(email: String, password: String, intent: AuthenticationIntent, requestID: UUID) async throws {
        guard !isSigningOut else { throw CancellationError() }
        revision = UUID()
        activeSignIn = requestID
        isRestoring = false
        isVerifying = false
        lastError = nil
        var grant: AuthenticationGrant?
        do {
            let response = try await service.authenticate(email: email, password: password, intent: intent)
            grant = response
            try checkSignIn(requestID)
            pendingGrant = response
            let user = try await service.commit(response)
            try checkSignIn(requestID)
            pendingGrant = nil
            activeSignIn = nil
            hasRestored = true
            identity = AuthenticationIdentity(sessionID: response.session.id, user: user)
            sessionExpired = false
        } catch {
            if let grant {
                do { try await service.discard(grant) }
                catch {
                    if activeSignIn == requestID || (activeSignIn == nil && user == nil) {
                        lastError = AuthenticationFailure.from(error)
                    }
                }
            }
            if activeSignIn == requestID {
                activeSignIn = nil
                pendingGrant = nil
            }
            throw error
        }
    }

    func cancelSignIn(requestID: UUID?) {
        guard let requestID, activeSignIn == requestID else { return }
        revision = UUID()
        let revision = revision
        activeSignIn = nil
        let grant = pendingGrant
        pendingGrant = nil
        if let grant {
            pendingDiscard = Task {
                do { try await service.discard(grant) }
                catch { if self.revision == revision { lastError = AuthenticationFailure.from(error) } }
            }
        }
    }

    func signOut() async throws {
        guard !isSigningOut else { return }
        cancelSignIn(requestID: activeSignIn)
        revision = UUID()
        isSigningOut = true
        isRestoring = false
        isVerifying = false
        defer { isSigningOut = false }
        do {
            try await service.signOut()
            identity = nil
            lastError = nil
            sessionExpired = false
            hasRestored = true
        } catch {
            lastError = AuthenticationFailure.from(error)
            throw error
        }
    }

    private func checkSignIn(_ requestID: UUID) throws {
        try Task.checkCancellation()
        guard activeSignIn == requestID else { throw CancellationError() }
    }
}
