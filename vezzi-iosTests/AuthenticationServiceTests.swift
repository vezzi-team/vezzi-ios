import Foundation
import Security
import XCTest
@testable import vezzi_ios

@MainActor
final class AuthenticationServiceTests: XCTestCase {
    func testLoginAndRegistrationMatchTheContractAndCommitOnlyAfterAcceptance() async throws {
        for intent in [AuthenticationIntent.signIn, .register] {
            let store = MemoryAuthenticationStore()
            let (service, server) = makeService(store: store) { _, _ in
                .json(AuthFixtures.authentication, status: intent == .register ? 201 : 200)
            }
            let grant = try await service.authenticate(email: "moti@example.com", password: "  secret  ", intent: intent)
            XCTAssertNil(store.snapshot)
            let user = try await service.commit(grant)
            XCTAssertEqual(user.id, AuthFixtures.user.id)
            XCTAssertEqual(store.snapshot?.tokens.refreshToken, "refresh-1")
            let request = try XCTUnwrap(server.requests.first)
            XCTAssertEqual(request.url?.path, intent == .register ? "/api/v1/auth/register" : "/api/v1/auth/login")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
            XCTAssertEqual(body?["password"], "  secret  ")
            XCTAssertEqual(body?["email"], "moti@example.com")
        }
    }

    func testParallelExpiredRequestsShareOneRefreshAndPersistTheRotatedPair() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true))
        let (service, server) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens, delay: 0.05) : .json(AuthFixtures.userJSON)
        }
        let users = try await withThrowingTaskGroup(of: AuthenticatedUser.self) { group in
            for _ in 0..<12 { group.addTask { try await service.currentUser() } }
            var users: [AuthenticatedUser] = []
            for try await user in group { users.append(user) }
            return users
        }
        XCTAssertEqual(users.count, 12)
        XCTAssertEqual(server.count("auth/refresh"), 1)
        XCTAssertEqual(store.snapshot?.tokens.accessToken, "access-2")
        XCTAssertEqual(store.snapshot?.tokens.refreshToken, "refresh-2")
        XCTAssertEqual(store.snapshot?.refreshPending, false)
        XCTAssertTrue(server.requests.filter { $0.url!.path.hasSuffix("users/me") }
            .allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-2" })
        XCTAssertTrue(store.savedSnapshots.first!.refreshPending)
    }

    func testConcurrentUnauthorizedResponsesDoNotRefreshAnAlreadyReplacedToken() async throws {
        let (service, server) = makeService { request, _ in
            if request.url!.path.hasSuffix("refresh") { return .json(AuthFixtures.rotatedTokens, delay: 0.03) }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1" {
                return .json("{}", status: 401, delay: 0.03)
            }
            return .json(AuthFixtures.userJSON)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await service.currentUser() } }
            try await group.waitForAll()
        }
        XCTAssertEqual(server.count("auth/refresh"), 1)
    }

    func testSecondUnauthorizedResponseStopsAndClearsTheSession() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved())
        let (service, server) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens) : .json("{}", status: 401)
        }
        do { _ = try await service.currentUser(); XCTFail("Expected expiration") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionExpired) }
        XCTAssertEqual(server.count("users/me"), 2)
        XCTAssertEqual(server.count("auth/refresh"), 1)
        XCTAssertNil(store.snapshot)
    }

    func testLogoutDuringRefreshNeverResurrectsTheSessionAndRevokesTheLatePair() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true))
        let (service, server) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens, delay: 0.15) : .empty
        }
        let request = Task { try await service.currentUser() }
        await waitUntil { server.count("auth/refresh") == 1 }
        try await service.signOut()
        do { _ = try await request.value; XCTFail("Late refresh must be ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(store.snapshot)
        let cached = try await service.cachedUser()
        XCTAssertNil(cached)
        await waitUntil {
            server.requests.contains { $0.url!.path.hasSuffix("logout") && String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains("refresh-2") == true }
        }
    }

    func testNewAccountCannotBeOverwrittenByAnOlderRefresh() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true))
        let (service, server) = makeService(store: store) { request, _ in
            if request.url!.path.hasSuffix("refresh") { return .json(AuthFixtures.rotatedTokens, delay: 0.15) }
            if request.url!.path.hasSuffix("login") { return .json(AuthFixtures.authentication) }
            return .empty
        }
        let old = Task { try await service.currentUser() }
        await waitUntil { server.count("auth/refresh") == 1 }
        let grant = try await service.authenticate(email: "moti@example.com", password: "secret", intent: .signIn)
        _ = try await service.commit(grant)
        _ = try? await old.value
        XCTAssertEqual(store.snapshot?.id, grant.session.id)
        XCTAssertEqual(store.snapshot?.tokens.accessToken, "access-1")
    }

    func testTimeoutDuringRefreshNeverReplaysTheOneTimeToken() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true))
        let (service, server) = makeService(store: store) { _, _ in .failure(.timedOut) }
        do { _ = try await service.currentUser(); XCTFail("Expected expiration") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionExpired) }
        _ = try? await service.currentUser()
        XCTAssertEqual(server.count("auth/refresh"), 1)
        XCTAssertNil(store.snapshot)
    }

    func testInterruptedRefreshMarkerRequiresSignInWithoutNetworkReplay() async throws {
        var interrupted = AuthFixtures.saved(expired: true)
        interrupted.refreshPending = true
        let store = MemoryAuthenticationStore(interrupted)
        let (service, server) = makeService(store: store) { _, _ in .json(AuthFixtures.rotatedTokens) }
        do { _ = try await service.cachedUser(); XCTFail("Expected expiration") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionExpired) }
        XCTAssertEqual(server.count("auth/refresh"), 0)
        XCTAssertEqual(server.count("users/me"), 0)
        XCTAssertNil(store.snapshot)
    }

    func testOfflineRefreshPreservesTheSavedSession() async throws {
        let saved = AuthFixtures.saved(expired: true)
        let store = MemoryAuthenticationStore(saved)
        let (service, server) = makeService(store: store) { _, _ in .failure(.notConnectedToInternet) }
        do { _ = try await service.currentUser(); XCTFail("Expected offline") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .offline) }
        XCTAssertEqual(store.snapshot, saved)
        XCTAssertEqual(server.count("auth/refresh"), 1)
    }

    func testServerFailureReadingUserPreservesCachedAccount() async throws {
        let saved = AuthFixtures.saved()
        let store = MemoryAuthenticationStore(saved)
        let (service, server) = makeService(store: store) { _, _ in .json("{}", status: 503) }
        do { _ = try await service.currentUser(); XCTFail("Expected failure") }
        catch { XCTAssertEqual((error as? APIError)?.status, 503) }
        XCTAssertEqual(store.snapshot, saved)
        XCTAssertEqual(server.count("auth/refresh"), 0)
    }

    func testStorageFailureBeforeRefreshDoesNotSendTheToken() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true), failingSaves: [1])
        let (service, server) = makeService(store: store) { _, _ in .json(AuthFixtures.rotatedTokens) }
        do { _ = try await service.currentUser(); XCTFail("Expected storage failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .storage) }
        XCTAssertTrue(server.requests.isEmpty)
        XCTAssertEqual(store.snapshot?.refreshPending, false)
    }

    func testRotatedPairIsRetainedInMemoryWhenPersistenceFails() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(expired: true), failingSaves: [2])
        let (service, server) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens) : .json(AuthFixtures.userJSON)
        }
        do { _ = try await service.currentUser(); XCTFail("Expected storage failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .storage) }
        XCTAssertEqual(store.snapshot?.refreshPending, true)
        _ = try await service.currentUser()
        XCTAssertEqual(server.count("auth/refresh"), 1)
        XCTAssertEqual(store.snapshot?.tokens.refreshToken, "refresh-2")
        XCTAssertEqual(store.snapshot?.refreshPending, false)
    }

    func testCancellingOneWaiterDoesNotCancelSharedRefresh() async throws {
        let (service, server) = makeService(store: MemoryAuthenticationStore(AuthFixtures.saved(expired: true))) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens, delay: 0.1) : .json(AuthFixtures.userJSON)
        }
        let first = Task { try await service.currentUser() }
        let second = Task { try await service.currentUser() }
        await waitUntil { server.count("auth/refresh") == 1 }
        first.cancel()
        _ = try? await first.value
        let user = try await second.value
        XCTAssertEqual(user, AuthFixtures.user)
        XCTAssertEqual(server.count("auth/refresh"), 1)
    }

    func testDiscardingAStaleGrantCannotClearANewerLogin() async throws {
        let store = MemoryAuthenticationStore()
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("logout") ? .empty : .json(AuthFixtures.authentication)
        }
        let first = try await service.authenticate(email: "a@example.com", password: "secret", intent: .signIn)
        let second = try await service.authenticate(email: "b@example.com", password: "secret", intent: .signIn)
        do { _ = try await service.commit(first); XCTFail("Stale grant must be rejected") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await service.commit(second)
        try await service.discard(first)
        XCTAssertEqual(store.snapshot?.id, second.session.id)
    }

    func testKeychainSaveFailureDoesNotPublishSuccessfulLogin() async throws {
        let store = MemoryAuthenticationStore(failingSaves: [1])
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("logout") ? .empty : .json(AuthFixtures.authentication)
        }
        let session = AuthenticationSession(service: service)
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.password = "password"
        model.submit(.signIn)
        await model.authenticate(using: session, successDuration: .zero)
        XCTAssertEqual(model.phase, .failure(.storage))
        XCTAssertNil(session.user)
        XCTAssertNil(store.snapshot)
    }

    func testLogoutStorageFailureKeepsTheAccountVisibleForRetry() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved(), failsRemoval: true)
        let (service, _) = makeService(store: store) { _, _ in .json(AuthFixtures.userJSON) }
        let session = AuthenticationSession(service: service)
        await session.restore()
        do { try await session.signOut(); XCTFail("Expected storage error") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .storage) }
        XCTAssertNotNil(session.user)
        XCTAssertNotNil(store.snapshot)
    }

    func testOfflineRestoreKeepsCachedUserAndExposesRetryableError() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved())
        let (service, _) = makeService(store: store) { _, _ in .failure(.notConnectedToInternet) }
        let session = AuthenticationSession(service: service, startsRestoring: true)
        await session.restore()
        XCTAssertEqual(session.user, AuthFixtures.user)
        XCTAssertEqual(session.lastError, .offline)
        XCTAssertFalse(session.isRestoring)
    }

    func testErrorEnvelopeVariantsHaveSafeLocalizedFallbacks() async throws {
        for payload in ["{\"code\":\"validation_error\",\"message\":\"bad input\",\"request_id\":\"test-id\",\"details\":{\"input\":\"secret\"}}",
                        "{\"detail\":[{\"loc\":[\"body\",\"password\"],\"input\":\"secret\",\"msg\":\"invalid\",\"type\":\"value_error\"}]}", "not json"] {
            let (service, _) = makeService { _, _ in .json(payload, status: 422) }
            do { _ = try await service.authenticate(email: "moti@example.com", password: "short", intent: .register); XCTFail("Expected error") }
            catch {
                XCTAssertEqual(AuthenticationFailure.from(error, intent: .register), .invalidInput)
                XCTAssertFalse(String(describing: error).contains("secret"))
            }
        }
    }

    func testRateLimitRespectsRetryAfterAndDoesNotRetryAutomatically() async throws {
        let (service, server) = makeService { _, _ in
            HTTPStubReply(status: 429, body: Data("{}".utf8), headers: ["Retry-After": "60"])
        }
        let model = LoginViewModel()
        let session = AuthenticationSession(service: service)
        model.email = "moti@example.com"
        model.password = "password"
        model.submit(.signIn)
        await model.authenticate(using: session, successDuration: .zero)
        guard case .failure(.rateLimited(let until)) = model.phase else { return XCTFail("Expected rate limit") }
        XCTAssertNotNil(until)
        model.password = "different"
        model.submit(.signIn)
        XCTAssertNil(model.request)
        XCTAssertEqual(server.count("auth/login"), 1)
    }

    func testClosingWhileCommitReturnsDiscardsTheSavedGrant() async throws {
        let store = MemoryAuthenticationStore()
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("logout") ? .empty : .json(AuthFixtures.authentication)
        }
        let session = AuthenticationSession(service: DelayedCommitService(base: service))
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.password = "password"
        model.submit(.signIn)
        let task = Task { await model.authenticate(using: session, successDuration: .zero) }
        await waitUntil { store.snapshot != nil }
        model.cancel(using: session)
        await task.value
        XCTAssertNil(session.user)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(model.phase, .idle)
    }

    func testLateRestorationCannotReplaceANewlySignedInUser() async throws {
        let store = MemoryAuthenticationStore(AuthFixtures.saved())
        let (service, server) = makeService(store: store) { request, _ in
            if request.url!.path.hasSuffix("login") {
                return .json(AuthFixtures.authentication.replacingOccurrences(of: "moti@example.com", with: "new@example.com"))
            }
            if request.url!.path.hasSuffix("logout") { return .empty }
            return .json(AuthFixtures.userJSON, delay: 0.15)
        }
        let session = AuthenticationSession(service: service)
        let restoring = Task { await session.restore() }
        await waitUntil { server.count("users/me") == 1 }
        try await session.signIn(email: "new@example.com", password: "password", intent: .signIn, requestID: UUID())
        await restoring.value
        XCTAssertEqual(session.user?.email, "new@example.com")
        XCTAssertEqual(store.snapshot?.user.email, "new@example.com")
    }

    func testKeychainStoresAndReplacesTheWholeSession() throws {
        let store = KeychainSessionStore(service: "vezzi.tests.auth.\(UUID().uuidString)")
        defer { try? store.remove() }
        do {
            let initial = try store.load()
            XCTAssertNil(initial)
        }
        catch AuthenticationStorageError.keychain(errSecMissingEntitlement) {
            throw XCTSkip("Keychain requires an app-hosted run with signing entitlements; CODE_SIGNING_ALLOWED=NO omits them.")
        }
        let first = AuthFixtures.saved()
        try store.save(first)
        XCTAssertEqual(try store.load(), first)
        var next = first
        next.tokens = AuthenticationTokens(accessToken: "access-2", refreshToken: "refresh-2", expiresIn: 3600)
        try store.save(next)
        XCTAssertEqual(try store.load(), next)
        try store.remove()
        XCTAssertNil(try store.load())
    }

    func testCancelledLoginCannotRestoreWhileRemovalFails() async throws {
        let store = MemoryAuthenticationStore(failsRemoval: true)
        let (service, server) = makeService(store: store) { request, _ in
            if request.url!.path.hasSuffix("logout") { return .empty }
            if request.url!.path.hasSuffix("users/me") { return .json(AuthFixtures.userJSON) }
            return .json(AuthFixtures.authentication)
        }
        let session = AuthenticationSession(service: DelayedCommitService(base: service, discardDelay: .milliseconds(40)))
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.password = "password"
        model.submit(.signIn)
        let task = Task { await model.authenticate(using: session, successDuration: .zero) }
        await waitUntil { store.snapshot != nil }
        let rejectedID = try XCTUnwrap(store.snapshot?.id)
        model.cancel(using: session)
        // Race foreground restoration against cancellation, without waiting for commit to return.
        await session.restore(force: true)
        await task.value
        XCTAssertNil(session.user)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(session.lastError, .sessionCleanupFailed)
        XCTAssertEqual(try store.invalidatedSessionID(), rejectedID)
        for _ in 0..<3 {
            await session.restore(force: true)
            XCTAssertNil(session.user)
            XCTAssertEqual(session.lastError, .sessionCleanupFailed)
        }
        XCTAssertEqual(server.count("users/me"), 0)
        XCTAssertEqual(server.count("auth/refresh"), 0)
        await waitUntil { server.count("auth/logout") >= 1 }
    }

    func testServerRejectionClearsAccountAndPreferencesEvenWhenRemovalFails() async throws {
        for rejectsRefresh in [true, false] {
            let store = MemoryAuthenticationStore(AuthFixtures.saved(), failsRemoval: true)
            let (service, server) = makeService(store: store) { request, _ in
                if request.url!.path.hasSuffix("logout") { return .empty }
                if request.url!.path.hasSuffix("refresh"), !rejectsRefresh { return .json(AuthFixtures.rotatedTokens) }
                return .json("{}", status: 401)
            }
            let session = AuthenticationSession(service: service)
            session.preferences.address = "Private address"
            await session.restore()
            XCTAssertNil(session.user)
            XCTAssertEqual(session.preferences.address, ProfilePreferences().address)
            XCTAssertEqual(session.lastError, .sessionCleanupFailed)
            for _ in 0..<3 { await session.restore(force: true) }
            XCTAssertNil(session.user)
            XCTAssertEqual(server.count("users/me"), rejectsRefresh ? 1 : 2)
            XCTAssertEqual(server.count("auth/refresh"), 1)
            XCTAssertEqual(try store.invalidatedSessionID(), store.snapshot?.id)
        }
    }

    func testRecreatedServiceRejectsCancelledRecordAndRetriesRemoval() async throws {
        let store = MemoryAuthenticationStore(failsRemoval: true)
        let (service, _) = makeService(store: store) { _, _ in .json(AuthFixtures.authentication) }
        let grant = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(grant)
        do { try await service.discard(grant); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }

        let (recreated, server) = makeService(store: store) { _, _ in .empty }
        let session = AuthenticationSession(service: recreated)
        await session.restore()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.lastError, .sessionCleanupFailed)
        store.allowRemoval()
        await session.restore(force: true)
        XCTAssertNil(session.user)
        XCTAssertNil(session.lastError)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(try store.invalidatedSessionID())
        XCTAssertEqual(server.count("users/me"), 0)
        XCTAssertEqual(server.count("auth/refresh"), 0)
    }

    func testLateDiscardAndStaleMarkerCannotDeleteOrRejectANewLogin() async throws {
        let store = MemoryAuthenticationStore(failsRemoval: true, failsClearingInvalidation: true)
        let (service, _) = makeService(store: store) { request, requests in
            if request.url!.path.hasSuffix("logout") { return .empty }
            let count = requests.filter { $0.url!.path.hasSuffix("login") }.count
            return .json(count == 1 ? AuthFixtures.authentication : AuthFixtures.authentication
                .replacingOccurrences(of: "access-1", with: "access-new").replacingOccurrences(of: "refresh-1", with: "refresh-new"))
        }
        let old = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(old)
        do { try await service.discard(old); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }
        let fresh = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(fresh)
        try await service.discard(old)
        XCTAssertEqual(store.snapshot?.id, fresh.session.id)
        XCTAssertEqual(try store.invalidatedSessionID(), old.session.id)

        let (recreated, server) = makeService(store: store) { _, _ in .json(AuthFixtures.userJSON) }
        let user = try await recreated.currentUser()
        XCTAssertEqual(user, fresh.session.user)
        XCTAssertEqual(store.snapshot?.id, fresh.session.id)
        XCTAssertEqual(server.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer access-new")
    }

    func testDiscardingPreviousGrantDoesNotCancelAnInFlightNewLogin() async throws {
        for failsRemoval in [false, true] {
            let store = MemoryAuthenticationStore(failsRemoval: failsRemoval)
            let (service, server) = makeService(store: store) { request, requests in
                if request.url!.path.hasSuffix("logout") { return .empty }
                let count = requests.filter { $0.url!.path.hasSuffix("login") }.count
                return count == 1 ? .json(AuthFixtures.authentication) : .json(AuthFixtures.nextAuthentication, delay: 0.15)
            }
            let old = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
            _ = try await service.commit(old)
            let incoming = Task { try await service.authenticate(email: "next@example.com", password: "password", intent: .signIn) }
            await waitUntil { server.count("auth/login") == 2 }
            do {
                try await service.discard(old)
                XCTAssertFalse(failsRemoval)
            } catch {
                XCTAssertTrue(failsRemoval)
                XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed)
            }
            let fresh = try await incoming.value
            _ = try await service.commit(fresh)
            XCTAssertNotEqual(fresh.session.id, old.session.id)
            XCTAssertNotEqual(fresh.session.user.id, old.session.user.id)
            XCTAssertEqual(store.snapshot?.id, fresh.session.id)
            XCTAssertEqual(store.snapshot?.user.email, "next@example.com")
            XCTAssertNil(try store.invalidatedSessionID())
            await waitUntil { server.count("auth/logout") >= 1 }
            XCTAssertTrue(server.requests.filter { $0.url!.path.hasSuffix("logout") }.allSatisfy {
                String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains("refresh-1") == true
            })
        }
    }

    func testClosingOldLoginDoesNotCancelNewLoginAtSessionBoundary() async throws {
        let store = MemoryAuthenticationStore()
        let (service, server) = makeService(store: store) { request, requests in
            if request.url!.path.hasSuffix("logout") { return .empty }
            let count = requests.filter { $0.url!.path.hasSuffix("login") }.count
            return count == 1 ? .json(AuthFixtures.authentication) : .json(AuthFixtures.nextAuthentication, delay: 0.15)
        }
        let session = AuthenticationSession(service: DelayedCommitService(base: service, discardDelay: .milliseconds(40)))
        let oldID = UUID()
        let previous = Task { try await session.signIn(email: "moti@example.com", password: "password", intent: .signIn, requestID: oldID) }
        await waitUntil { store.snapshot != nil }
        session.cancelSignIn(requestID: oldID)
        let incoming = Task { try await session.signIn(email: "next@example.com", password: "password", intent: .signIn, requestID: UUID()) }
        await waitUntil { server.count("auth/login") == 2 }
        do { try await previous.value; XCTFail("The old attempt must remain cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        try await incoming.value
        XCTAssertEqual(session.user?.email, "next@example.com")
        XCTAssertNotEqual(session.user?.id, AuthFixtures.user.id)
        XCTAssertEqual(store.snapshot?.user, session.user)
        XCTAssertNil(session.lastError)
    }

    func testPendingRemovalRetryDoesNotCancelAnInFlightNewLogin() async throws {
        let store = MemoryAuthenticationStore(failsRemoval: true)
        let (service, server) = makeService(store: store) { request, requests in
            if request.url!.path.hasSuffix("logout") { return .empty }
            let count = requests.filter { $0.url!.path.hasSuffix("login") }.count
            return count == 1 ? .json(AuthFixtures.authentication) : .json(AuthFixtures.nextAuthentication, delay: 0.15)
        }
        let old = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(old)
        do { try await service.discard(old); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }
        let incoming = Task { try await service.authenticate(email: "next@example.com", password: "password", intent: .signIn) }
        await waitUntil { server.count("auth/login") == 2 }
        store.allowRemoval()
        try await service.discard(old)
        let fresh = try await incoming.value
        _ = try await service.commit(fresh)
        XCTAssertEqual(store.snapshot?.id, fresh.session.id)
        XCTAssertEqual(store.snapshot?.user.email, "next@example.com")
        XCTAssertNil(try store.invalidatedSessionID())
    }

    func testDiscardedGrantCannotBeCommittedAgainEvenWhenRemovalFails() async throws {
        for failsRemoval in [false, true] {
            let store = MemoryAuthenticationStore(failsRemoval: failsRemoval)
            let (service, _) = makeService(store: store) { request, _ in
                request.url!.path.hasSuffix("logout") ? .empty : .json(AuthFixtures.authentication)
            }
            let grant = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
            _ = try await service.commit(grant)
            do {
                try await service.discard(grant)
                XCTAssertFalse(failsRemoval)
            } catch {
                XCTAssertTrue(failsRemoval)
                XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed)
            }
            do { _ = try await service.commit(grant); XCTFail("A cancelled grant must not be accepted again") }
            catch { XCTAssertTrue(error is CancellationError) }
            store.allowRemoval()
            let cached = try await service.cachedUser()
            XCTAssertNil(cached)
            XCTAssertNil(store.snapshot)
        }
    }

    func testFailedReplacementKeepsTheOldRecordRejected() async throws {
        let store = MemoryAuthenticationStore(failingSaves: [2], failsRemoval: true)
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("logout") ? .empty : .json(AuthFixtures.authentication)
        }
        let old = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(old)
        do { try await service.discard(old); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }
        let fresh = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        do { _ = try await service.commit(fresh); XCTFail("Expected save failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .storage) }
        try await service.discard(fresh)
        XCTAssertEqual(store.snapshot?.id, old.session.id)
        XCTAssertEqual(try store.invalidatedSessionID(), old.session.id)
        let (recreated, server) = makeService(store: store) { _, _ in .empty }
        let session = AuthenticationSession(service: recreated)
        await session.restore()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.lastError, .sessionCleanupFailed)
        XCTAssertEqual(server.count("users/me"), 0)
        XCTAssertEqual(server.count("auth/refresh"), 0)
    }

    func testInterruptedOrMalformedStoredSessionIsRejectedWhenRemovalFails() async throws {
        for isInterrupted in [true, false] {
            var saved = AuthFixtures.saved()
            if isInterrupted {
                saved.refreshPending = true
            } else {
                saved.tokens = AuthenticationTokens(accessToken: "", refreshToken: "refresh-1", expiresIn: 1800)
            }
            let store = MemoryAuthenticationStore(saved, failsRemoval: true)
            let (service, server) = makeService(store: store) { _, _ in .empty }
            let session = AuthenticationSession(service: service)
            await session.restore()
            await session.restore(force: true)
            XCTAssertNil(session.user)
            XCTAssertEqual(session.lastError, .sessionCleanupFailed)
            XCTAssertEqual(try store.invalidatedSessionID(), saved.id)
            XCTAssertEqual(server.count("users/me"), 0)
            XCTAssertEqual(server.count("auth/refresh"), 0)
        }
    }

    func testDeletionStillRunsWhenWritingInvalidationFails() async throws {
        let store = MemoryAuthenticationStore(failsInvalidation: true)
        let (service, _) = makeService(store: store) { _, _ in .json(AuthFixtures.authentication) }
        let grant = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(grant)
        try await service.discard(grant)
        XCTAssertNil(store.snapshot)
        let cached = try await service.cachedUser()
        XCTAssertNil(cached)
    }

    func testBothStorageFailuresStillBlockTheSessionInMemoryAndAllowCleanupRetry() async throws {
        let store = MemoryAuthenticationStore(failsRemoval: true, failsInvalidation: true)
        let (service, server) = makeService(store: store) { _, _ in .json(AuthFixtures.authentication) }
        let grant = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(grant)
        do { try await service.discard(grant); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }
        let session = AuthenticationSession(service: service)
        await session.restore()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.lastError, .sessionCleanupFailed)
        store.allowRemoval()
        await session.restore(force: true)
        XCTAssertNil(session.user)
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(server.count("users/me"), 0)
    }

    func testKeychainInvalidationFileSurvivesStoreRecreationAndContainsOnlyTheSessionID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("invalidated.json")
        let serviceName = "vezzi.tests.auth.\(UUID().uuidString)"
        let store = KeychainSessionStore(service: serviceName, invalidationURL: url)
        defer {
            try? store.remove()
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let initial = try store.load()
            XCTAssertNil(initial)
        }
        catch AuthenticationStorageError.keychain(errSecMissingEntitlement) {
            throw XCTSkip("Keychain requires a signed app-hosted run.")
        }
        XCTAssertNil(try store.invalidatedSessionID())
        let (service, _) = makeService(store: RemovalFailingStore(base: store)) { _, _ in .json(AuthFixtures.authentication) }
        let grant = try await service.authenticate(email: "moti@example.com", password: "password", intent: .signIn)
        _ = try await service.commit(grant)
        do { try await service.discard(grant); XCTFail("Expected cleanup failure") }
        catch { XCTAssertEqual(error as? AuthenticationFailure, .sessionCleanupFailed) }
        XCTAssertEqual(try store.load()?.id, grant.session.id)
        XCTAssertEqual(try JSONDecoder().decode(UUID.self, from: Data(contentsOf: url)), grant.session.id)

        let reopened = KeychainSessionStore(service: serviceName, invalidationURL: url)
        XCTAssertEqual(try reopened.invalidatedSessionID(), grant.session.id)
        let (recreated, server) = makeService(store: reopened) { _, _ in .empty }
        let session = AuthenticationSession(service: recreated)
        await session.restore()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.lastError, .sessionExpired)
        XCTAssertNil(try reopened.load())
        XCTAssertNil(try reopened.invalidatedSessionID())
        XCTAssertEqual(server.count("users/me"), 0)
        XCTAssertEqual(server.count("auth/refresh"), 0)
    }

    func testCorruptInvalidationFileFailsClosedWithoutRemovingValidCredentials() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("invalidated.json")
        let store = KeychainSessionStore(service: "vezzi.tests.auth.\(UUID().uuidString)", invalidationURL: url)
        defer {
            try? store.remove()
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            let initial = try store.load()
            XCTAssertNil(initial)
        }
        catch AuthenticationStorageError.keychain(errSecMissingEntitlement) {
            throw XCTSkip("Keychain requires a signed app-hosted run.")
        }
        let saved = AuthFixtures.saved()
        try store.save(saved)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a UUID".utf8).write(to: url)
        let (service, server) = makeService(store: store) { _, _ in .empty }
        let session = AuthenticationSession(service: service)
        await session.restore()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.lastError, .storage)
        XCTAssertEqual(try store.load(), saved)
        XCTAssertTrue(server.requests.isEmpty)
    }

    private func makeService(store: any AuthenticationSessionStore = MemoryAuthenticationStore(AuthFixtures.saved()),
                             handler: @escaping @Sendable (URLRequest, [URLRequest]) -> HTTPStubReply)
        -> (DefaultAuthenticationService, AuthenticationHTTPStub) {
        let server = AuthenticationHTTPStub(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "https://\(server.host)/api/v1/")!, session: session)
        addTeardownBlock {
            session.invalidateAndCancel()
            AuthenticationURLProtocol.unregister(server.host)
        }
        return (DefaultAuthenticationService(client: client, store: store), server)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Condition timed out", file: file, line: line)
    }
}

nonisolated private enum AuthFixtures {
    static let user = AuthenticatedUser(id: UUID(uuidString: "091D32C0-01E0-434E-91F4-92D6E0564ACA")!,
                                        email: "moti@example.com", role: "user", createdAt: Date(timeIntervalSince1970: 0))
    static let userJSON = #"{"id":"091D32C0-01E0-434E-91F4-92D6E0564ACA","email":"moti@example.com","role":"user","created_at":"1970-01-01T00:00:00Z"}"#
    static let tokens = #"{"access_token":"access-1","refresh_token":"refresh-1","expires_in":1800,"token_type":"bearer"}"#
    static let rotatedTokens = #"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":1800,"token_type":"bearer"}"#
    static let authentication = "{\"user\":\(userJSON),\"tokens\":\(tokens)}"
    static let nextAuthentication = authentication
        .replacingOccurrences(of: user.id.uuidString, with: "0d926ad4-9a66-4b36-b5bf-7d6b977e44bc")
        .replacingOccurrences(of: user.email, with: "next@example.com")
        .replacingOccurrences(of: "access-1", with: "access-next")
        .replacingOccurrences(of: "refresh-1", with: "refresh-next")
    static func saved(expired: Bool = false) -> StoredAuthentication {
        StoredAuthentication(user: user, tokens: AuthenticationTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 1800),
                             receivedAt: Date().addingTimeInterval(expired ? -3600 : 0))
    }
}

nonisolated private final class MemoryAuthenticationStore: AuthenticationSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: StoredAuthentication?
    private var saves = 0
    private var history: [StoredAuthentication] = []
    private let failingSaves: Set<Int>
    private var removalUnavailable: Bool
    private var invalidatedID: UUID?
    private let failsInvalidation: Bool
    private let failsClearingInvalidation: Bool

    init(_ value: StoredAuthentication? = nil, failingSaves: Set<Int> = [], failsRemoval: Bool = false,
         failsInvalidation: Bool = false, failsClearingInvalidation: Bool = false) {
        self.value = value
        self.failingSaves = failingSaves
        self.removalUnavailable = failsRemoval
        self.failsInvalidation = failsInvalidation
        self.failsClearingInvalidation = failsClearingInvalidation
    }
    var snapshot: StoredAuthentication? { lock.withLock { value } }
    var savedSnapshots: [StoredAuthentication] { lock.withLock { history } }
    func load() throws -> StoredAuthentication? { snapshot }
    func save(_ session: StoredAuthentication) throws {
        try lock.withLock {
            saves += 1
            if failingSaves.contains(saves) { throw AuthenticationFailure.storage }
            value = session
            history.append(session)
        }
    }
    func remove() throws {
        try lock.withLock {
            if removalUnavailable { throw AuthenticationFailure.storage }
            value = nil
        }
    }
    func allowRemoval() { lock.withLock { removalUnavailable = false } }
    func invalidatedSessionID() throws -> UUID? { lock.withLock { invalidatedID } }
    func markInvalidated(_ id: UUID) throws {
        try lock.withLock {
            if failsInvalidation { throw AuthenticationStorageError.invalidationFile }
            invalidatedID = id
        }
    }
    func clearInvalidation() throws {
        try lock.withLock {
            if failsClearingInvalidation { throw AuthenticationStorageError.invalidationFile }
            invalidatedID = nil
        }
    }
}

nonisolated private struct HTTPStubReply: Sendable {
    var status = 200
    var body = Data()
    var headers: [String: String] = [:]
    var delay: TimeInterval = 0
    var error: URLError?
    static var empty: Self { Self(status: 204) }
    static func json(_ text: String, status: Int = 200, delay: TimeInterval = 0) -> Self {
        Self(status: status, body: Data(text.utf8), headers: ["Content-Type": "application/json"], delay: delay)
    }
    static func failure(_ code: URLError.Code) -> Self { Self(error: URLError(code)) }
}

nonisolated private final class AuthenticationHTTPStub: @unchecked Sendable {
    let host = UUID().uuidString.lowercased() + ".invalid"
    private let lock = NSLock()
    private var received: [URLRequest] = []
    private let handler: @Sendable (URLRequest, [URLRequest]) -> HTTPStubReply
    init(handler: @escaping @Sendable (URLRequest, [URLRequest]) -> HTTPStubReply) {
        self.handler = handler
        AuthenticationURLProtocol.register(self)
    }
    var requests: [URLRequest] { lock.withLock { received } }
    func count(_ suffix: String) -> Int { requests.filter { $0.url!.path.hasSuffix(suffix) }.count }
    func response(to request: URLRequest) -> HTTPStubReply {
        lock.withLock {
            received.append(request)
            return handler(request, received)
        }
    }
}

nonisolated private final class AuthenticationURLProtocol: URLProtocol, @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var servers: [String: AuthenticationHTTPStub] = [:]
    }
    private static let registry = Registry()
    private let lock = NSLock()
    private var stopped = false

    static func register(_ server: AuthenticationHTTPStub) { registry.lock.withLock { registry.servers[server.host] = server } }
    static func unregister(_ host: String) { _ = registry.lock.withLock { registry.servers.removeValue(forKey: host) } }
    override class func canInit(with request: URLRequest) -> Bool {
        registry.lock.withLock { registry.servers[request.url?.host ?? ""] != nil }
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let server = Self.registry.lock.withLock({ Self.registry.servers[request.url?.host ?? ""] }) else { return }
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(bytes, count: count)
            }
            captured.httpBody = body
        }
        let reply = server.response(to: captured)
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !lock.withLock({ stopped }) else { return }
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: reply.body)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() { lock.withLock { stopped = true } }
}

nonisolated private struct DelayedCommitService: AuthenticationService {
    let base: DefaultAuthenticationService
    var discardDelay: Duration = .zero
    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        try await base.authenticate(email: email, password: password, intent: intent)
    }
    func commit(_ grant: AuthenticationGrant) async throws -> AuthenticatedUser {
        let user = try await base.commit(grant)
        try await Task.sleep(for: .milliseconds(100))
        return user
    }
    func discard(_ grant: AuthenticationGrant) async throws {
        try await Task.sleep(for: discardDelay)
        try await base.discard(grant)
    }
    func cachedUser() async throws -> AuthenticatedUser? { try await base.cachedUser() }
    func currentUser() async throws -> AuthenticatedUser { try await base.currentUser() }
    func signOut() async throws { try await base.signOut() }
}

nonisolated private struct RemovalFailingStore: AuthenticationSessionStore {
    let base: KeychainSessionStore
    func load() throws -> StoredAuthentication? { try base.load() }
    func save(_ session: StoredAuthentication) throws { try base.save(session) }
    func remove() throws { throw AuthenticationStorageError.keychain(errSecInteractionNotAllowed) }
    func invalidatedSessionID() throws -> UUID? { try base.invalidatedSessionID() }
    func markInvalidated(_ id: UUID) throws { try base.markInvalidated(id) }
    func clearInvalidation() throws { try base.clearInvalidation() }
}
