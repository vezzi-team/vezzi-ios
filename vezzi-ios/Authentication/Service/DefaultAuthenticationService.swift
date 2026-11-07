import Foundation

actor DefaultAuthenticationService: AuthenticationService {
    private let client: APIClient
    private let store: any AuthenticationSessionStore
    private let now: @Sendable () -> Date
    private var stored: StoredAuthentication?
    private var hasLoaded = false
    private var needsPersistence = false
    private var pendingRemoval: UUID?
    private var generation = UUID()
    private var refreshFlight: (id: UUID, task: Task<StoredAuthentication, Error>)?

    init(client: APIClient = APIClient(), store: any AuthenticationSessionStore = KeychainSessionStore(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
    }

    // MARK: - Sign in

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        try Task.checkCancellation()
        let attempt = UUID()
        generation = attempt
        refreshFlight = nil
        let credentials = AuthenticationCredentials(email: email, password: password)
        let response: AuthenticationResponse = try await client.send(
            intent == .register ? "auth/register" : "auth/login", method: "POST", body: APIClient.encode(credentials)
        )
        guard response.tokens.isValid else { throw APIError.invalidResponse }
        guard generation == attempt else {
            revoke(response.tokens.refreshToken)
            throw CancellationError()
        }
        return AuthenticationGrant(generation: attempt,
                                   session: StoredAuthentication(user: response.user, tokens: response.tokens, receivedAt: now()))
    }

    func commit(_ grant: AuthenticationGrant) throws -> AuthenticatedUser {
        try Task.checkCancellation()
        guard generation == grant.generation else { throw CancellationError() }
        try store.save(grant.session)
        // A successful replacement makes cleanup of the previous record obsolete.
        pendingRemoval = nil
        try? store.clearInvalidation()
        let previous = stored
        stored = grant.session
        hasLoaded = true
        needsPersistence = false
        if let previous, previous.id != grant.session.id { revoke(previous.tokens.refreshToken) }
        return grant.session.user
    }

    func discard(_ grant: AuthenticationGrant) throws {
        if generation == grant.generation { generation = UUID() }
        if stored?.id == grant.session.id {
            // Clearing this grant must preserve the generation of any newer authentication attempt.
            try clearStoredSession()
        } else if pendingRemoval == grant.session.id {
            try retryRemoval()
        } else {
            revoke(grant.session.tokens.refreshToken)
        }
    }

    // MARK: - Restore and authorized requests

    func cachedUser() throws -> AuthenticatedUser? {
        try loadIfNeeded()
        return stored?.user
    }

    func currentUser() async throws -> AuthenticatedUser {
        try Task.checkCancellation()
        try loadIfNeeded()
        guard let initial = stored else { throw AuthenticationFailure.sessionExpired }
        let epoch = generation
        let active = try await validSession()
        let user: AuthenticatedUser
        do {
            user = try await client.send("users/me", accessToken: active.tokens.accessToken)
        } catch let error as APIError where error.status == 401 {
            try checkSession(id: initial.id, generation: epoch)
            let renewed = try await refresh(rejectedToken: active.tokens.accessToken)
            do {
                user = try await client.send("users/me", accessToken: renewed.tokens.accessToken)
            } catch let error as APIError where error.status == 401 {
                try checkSession(id: initial.id, generation: epoch)
                try invalidate()
                throw AuthenticationFailure.sessionExpired
            }
        }
        try Task.checkCancellation()
        try checkSession(id: initial.id, generation: epoch)
        // Preserve any tokens rotated by another request while /me was in flight.
        if var latest = stored, latest.user != user {
            latest.user = user
            stored = latest
            needsPersistence = true
            try persistLatest()
        }
        return user
    }

    func signOut() throws {
        let previous = stored ?? (try? store.load())
        // Report a failed local removal: otherwise the next launch could silently sign in again.
        try store.remove()
        pendingRemoval = nil
        try? store.clearInvalidation()
        generation = UUID()
        stored = nil
        hasLoaded = true
        needsPersistence = false
        refreshFlight = nil
        if let previous { revoke(previous.tokens.refreshToken) }
    }

    // MARK: - One-time refresh

    private func validSession() async throws -> StoredAuthentication {
        try loadIfNeeded()
        guard let stored else { throw AuthenticationFailure.sessionExpired }
        let margin = min(30, TimeInterval(stored.tokens.expiresIn) / 10)
        if refreshFlight != nil || stored.refreshPending || stored.expiresAt <= now().addingTimeInterval(margin) {
            return try await refresh()
        }
        return stored
    }

    private func refresh(rejectedToken: String? = nil) async throws -> StoredAuthentication {
        try loadIfNeeded()
        guard let current = stored else { throw AuthenticationFailure.sessionExpired }
        if let flight = refreshFlight { return try await flight.task.value }
        if let rejectedToken, rejectedToken != current.tokens.accessToken { return current }
        guard !current.refreshPending else {
            try invalidate()
            throw AuthenticationFailure.sessionExpired
        }
        let id = UUID()
        let epoch = generation
        // Cancellation of an individual waiter must not cancel a shared one-time exchange.
        let task = Task { try await self.performRefresh(current, generation: epoch) }
        refreshFlight = (id, task)
        defer { if refreshFlight?.id == id { refreshFlight = nil } }
        return try await task.value
    }

    private func performRefresh(_ previous: StoredAuthentication, generation epoch: UUID) async throws -> StoredAuthentication {
        try checkSession(id: previous.id, generation: epoch)
        var pending = previous
        pending.refreshPending = true
        // An interrupted process must not replay the old refresh token on relaunch.
        try store.save(pending)
        stored = pending
        do {
            let tokens: AuthenticationTokens = try await client.send(
                "auth/refresh", method: "POST", body: APIClient.encode(RefreshCredentials(refreshToken: previous.tokens.refreshToken))
            )
            guard tokens.isValid else { throw APIError.invalidResponse }
            guard generation == epoch, stored?.id == previous.id else {
                revoke(tokens.refreshToken)
                throw CancellationError()
            }
            var updated = previous
            updated.tokens = tokens
            updated.expiresAt = now().addingTimeInterval(TimeInterval(tokens.expiresIn))
            stored = updated
            needsPersistence = true
            try persistLatest()
            return updated
        } catch {
            try checkSession(id: previous.id, generation: epoch)
            if needsPersistence { throw AuthenticationFailure.storage }
            if Self.definitelyNotSent(error) || (error as? APIError)?.status == 429 {
                stored = previous
                needsPersistence = true
                try persistLatest()
                throw AuthenticationFailure.from(error)
            }
            // A lost response or 5xx may follow a rotation. Without server-side recovery, require sign-in.
            try invalidate()
            throw AuthenticationFailure.sessionExpired
        }
    }

    // MARK: - Storage and fencing

    private func loadIfNeeded() throws {
        if !hasLoaded {
            let saved = try store.load()
            let invalidatedID = try store.invalidatedSessionID()
            stored = saved
            hasLoaded = true
            if let saved, saved.refreshPending || !saved.tokens.isValid || saved.id == invalidatedID {
                try invalidate()
                throw AuthenticationFailure.sessionExpired
            }
            if invalidatedID != nil { try? store.clearInvalidation() }
        }
        try retryRemoval()
        try persistLatest()
    }

    private func persistLatest() throws {
        guard needsPersistence, let stored else { return }
        try store.save(stored)
        needsPersistence = false
    }

    private func checkSession(id: UUID, generation epoch: UUID) throws {
        guard generation == epoch, stored?.id == id else { throw CancellationError() }
    }

    private func invalidate() throws {
        generation = UUID()
        try clearStoredSession()
    }

    private func clearStoredSession() throws {
        let previous = stored
        stored = nil
        hasLoaded = true
        needsPersistence = false
        refreshFlight = nil
        if let previous {
            pendingRemoval = previous.id
            revoke(previous.tokens.refreshToken)
        }
        try retryRemoval()
    }

    private func retryRemoval() throws {
        guard let id = pendingRemoval else { return }
        // Try both persistence channels: deletion can still succeed if writing the marker fails.
        try? store.markInvalidated(id)
        do { try store.remove() }
        catch { throw AuthenticationFailure.sessionCleanupFailed }
        pendingRemoval = nil
        // A leftover UUID cannot reject a future session, which always has a fresh identity.
        try? store.clearInvalidation()
    }

    private func revoke(_ refreshToken: String) {
        let client = client
        Task {
            // Local logout is independent of connectivity. URLSession bounds this best-effort revocation.
            try? await client.sendWithoutResponse("auth/logout", method: "POST",
                                                  body: APIClient.encode(RefreshCredentials(refreshToken: refreshToken)))
        }
    }

    private static func definitelyNotSent(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost].contains(error.code)
    }
}
