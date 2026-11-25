import Foundation
import Security
import XCTest
@testable import vezzi_ios

@MainActor
final class AuthenticationServiceTests: XCTestCase {
    func testPublicSessionIdentitySurvivesRotationAndServiceRecreation() async throws {
        let saved = AuthFixtures.saved(expired: true)
        let store = MemoryAuthenticationStore(saved)
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("refresh") ? .json(AuthFixtures.rotatedTokens) : .json(AuthFixtures.userJSON)
        }
        let before = try await service.cachedIdentity()
        XCTAssertEqual(before?.sessionID, saved.id)
        _ = try await service.currentUser()
        let after = try await service.cachedIdentity()
        XCTAssertEqual(after?.sessionID, saved.id)
        let (recreated, _) = makeService(store: store) { _, _ in .json(AuthFixtures.userJSON) }
        let restored = try await recreated.cachedIdentity()
        XCTAssertEqual(restored, after)
    }

    func testDependenciesPublishNewSessionEvenWhenTheUserIsUnchanged() async throws {
        let saved = AuthFixtures.saved()
        let store = MemoryAuthenticationStore(saved)
        let (service, _) = makeService(store: store) { request, _ in
            request.url!.path.hasSuffix("login") ? .json(AuthFixtures.authentication) : .json(AuthFixtures.userJSON)
        }
        let dependencies = AppDependencies(cache: nil, authenticationService: service)
        await dependencies.authentication.restore()
        XCTAssertEqual(dependencies.shoppingList.account?.sessionID, saved.id)
        dependencies.shoppingList.selection.setQuantity(2, for: "1")
        try await dependencies.authentication.signIn(email: "moti@example.com", password: "secret123",
                                                     intent: .signIn, requestID: UUID())
        let identity = try XCTUnwrap(dependencies.authentication.identity)
        XCTAssertEqual(identity.user.id, saved.user.id)
        XCTAssertNotEqual(identity.sessionID, saved.id)
        XCTAssertEqual(dependencies.shoppingList.account?.sessionID, identity.sessionID)
        XCTAssertTrue(dependencies.shoppingList.selection.quantities.isEmpty)
    }

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
        let cached = (try await service.cachedIdentity())?.user
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
        do { _ = (try await service.cachedIdentity())?.user; XCTFail("Expected expiration") }
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

    func testServerRejectionClearsAccountEvenWhenRemovalFails() async throws {
        for rejectsRefresh in [true, false] {
            let store = MemoryAuthenticationStore(AuthFixtures.saved(), failsRemoval: true)
            let (service, server) = makeService(store: store) { request, _ in
                if request.url!.path.hasSuffix("logout") { return .empty }
                if request.url!.path.hasSuffix("refresh"), !rejectsRefresh { return .json(AuthFixtures.rotatedTokens) }
                return .json("{}", status: 401)
            }
            let session = AuthenticationSession(service: service)
            await session.restore()
            XCTAssertNil(session.user)
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
            let cached = (try await service.cachedIdentity())?.user
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
        let cached = (try await service.cachedIdentity())?.user
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
        await waitUntil { server.count("auth/logout") == 1 }
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

    func testPublicAnalogsPreserveServerRankAndJoinPricesForTheSelectedStore() async throws {
        func row(_ id: Int) -> String {
            #"{"id":\#(id),"name":"Product \#(id)","category":"Food","package_amount":200,"package_unit":"g","similarity":0.7,"min_price_kopecks":3000}"#
        }
        let payload = "[" + [7, 9, 9, 3, 1, 5].map(row).joined(separator: ",") + "]"
        let (client, server) = makeClient { _, _ in .json(payload) }
        let repository = DefaultCatalogRepository(source: APICatalogSource(client: client))
        let products = [7, 9, 3, 1, 5].map { CatalogProduct(id: String($0), name: "Product \($0)", category: "Food") }
        let stores = [CatalogStore(id: "a", name: "A"), CatalogStore(id: "b", name: "B"), CatalogStore(id: "c", name: "C")]
        let offers = [
            CatalogOffer(id: "a9", productID: "9", storeID: "a", price: 100, currency: "RUB", inStock: true),
            CatalogOffer(id: "b9", productID: "9", storeID: "b", price: 30, currency: "RUB", inStock: true),
            CatalogOffer(id: "a3", productID: "3", storeID: "a", price: 80, currency: "RUB", inStock: false),
            CatalogOffer(id: "a1", productID: "1", storeID: "a", price: 70, currency: "RUB", inStock: true),
            CatalogOffer(id: "c9", productID: "9", storeID: "c", price: 30, currency: "RUB", inStock: false),
            CatalogOffer(id: "a5", productID: "5", storeID: "a", price: 40, currency: "RUB", inStock: true),
            CatalogOffer(id: "c5", productID: "5", storeID: "c", price: 60, currency: "RUB", inStock: true)
        ]
        try await repository.importCatalog(CatalogImport(products: products, stores: stores, offers: offers))

        let all = await repository.alternativeProducts(for: "7")
        XCTAssertEqual(all.map(\.id), ["9", "3", "1"])
        XCTAssertEqual(all.first?.lowestPrice, 30)
        let search = SearchViewModel(repository: repository)
        let scoped = await search.alternatives(for: "7", storeID: "a")
        XCTAssertEqual(scoped.map(\.id), ["9", "1"])
        XCTAssertEqual(scoped.map(\.lowestPrice), [100, 70])
        XCTAssertEqual(scoped.flatMap(\.offers).map(\.storeID), ["a", "a"])
        let local = await repository.alternativeProducts(for: "7", storeID: "c")
        XCTAssertEqual(local.map(\.id), ["5"])
        XCTAssertEqual(local.flatMap(\.offers).map(\.id), ["c5"])
        XCTAssertEqual(server.requests.count, 3)
        for request in server.requests {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/products/7/analogs")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        }
    }

    func testOfflineAndEmptyServerAnalogsUseTheCachedGroup() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogFixtures.snapshot(CatalogImport(products: [
            CatalogProduct(id: "7", name: "Original", productType: "milk"),
            CatalogProduct(id: "9", name: "Other milk", productType: "milk"),
            CatalogProduct(id: "10", name: "Bread", productType: "bread")
        ]))
        let (client, server) = makeClient { _, requests in
            switch requests.count {
            case 1: .failure(.networkConnectionLost)
            case 2: .failure(.timedOut)
            default: .json("[]")
            }
        }
        let repository = DefaultCatalogRepository(cache: cache, source: APICatalogSource(client: client))
        repository.updateConnectivity(isConnected: false)
        let offline = await repository.alternativeProducts(for: "7")
        XCTAssertEqual(offline.map(\.id), ["9"])
        XCTAssertTrue(server.requests.isEmpty)

        repository.updateConnectivity(isConnected: true)
        let interrupted = await repository.alternativeProducts(for: "7")
        XCTAssertEqual(interrupted.map(\.id), ["9"])
        let timedOut = await repository.alternativeProducts(for: "7")
        XCTAssertEqual(timedOut.map(\.id), ["9"])
        let reopened = DefaultCatalogRepository(cache: cache, source: APICatalogSource(client: client))
        let local = await reopened.alternativeProducts(for: "7")
        XCTAssertEqual(local.map(\.id), ["9"])
        let noAlternatives = await reopened.alternativeProducts(for: "10")
        XCTAssertTrue(noAlternatives.isEmpty)
        XCTAssertEqual(server.requests.count, 4)
    }

    func testOpenDetailResolvesRankedAndLocalAnalogsWhenInitialExportArrives() async throws {
        let root = #"{"id":77,"name":"Original milk","category":"Dairy","product_type":"milk","package_amount":1,"package_unit":"l"}"#
        let analog = #"{"id":42,"name":"Milk","category":"Dairy","product_type":"milk","package_amount":930.5,"package_unit":"ml","min_price_kopecks":8999,"similarity":0.7}"#
        let export = CatalogAPIFixture.json.replacingOccurrences(of: #""products":["#, with: #""products":["# + root + ",")
        let scenarios: [(response: String, cachedIDs: [String])] = [
            ("[]", []), ("[\(analog)]", []), ("[]", ["77"]), ("[\(analog)]", ["77"])
        ]
        for (response, cachedIDs) in scenarios {
            let (client, server) = makeClient { request, _ in
                switch request.url?.lastPathComponent {
                case "export": .json(export, delay: 0.5)
                case "search": .json("[\(root)]")
                case "analogs": .json(response)
                default: .json("{}", status: 404)
                }
            }
            let cache = ControlledCatalogCache()
            cache.snapshot = try CatalogFixtures.snapshot(CatalogImport(products: cachedIDs.map {
                CatalogProduct(id: $0, name: "Original milk", productType: "milk")
            }))
            let repository = DefaultCatalogRepository(cache: cache, source: APICatalogSource(client: client))
            let refresh = Task { try await repository.refresh() }
            await waitUntil { server.count("/export") == 1 }
            guard case .items(let results) = await repository.searchProducts(matching: "Original") else {
                return XCTFail("Expected the server search result before the export")
            }
            let rows = await publishedItems(results, where: { !$0.isEmpty })
            let productID = try XCTUnwrap(rows.first?.id)
            let detail = ProductDetailViewModel()
            let load: (String) async -> [Product] = { await repository.alternativeProducts(for: $0) }
            await detail.loadAlternatives(for: productID, using: load)
            let items = detail.alternatives(for: productID)
            XCTAssertEqual(items.map(\.id), ["42"])
            XCTAssertEqual(items.first?.lowestPrice, Decimal(string: "89.99"))
            XCTAssertEqual(items.first?.offers.map(\.storeID), ["7"])
            try await refresh.value
            await detail.loadAlternatives(for: productID, using: load)
            XCTAssertEqual(server.count("/analogs"), 1)
            XCTAssertEqual(server.count("/export"), 1)
        }
    }

    func testFailedInitialExportSettlesEmptyAlternativesWithoutACache() async {
        let (client, server) = makeClient { request, _ in
            .json("{}", status: 503, delay: request.url?.lastPathComponent == "export" ? 0.2 : 0)
        }
        let repository = DefaultCatalogRepository(source: APICatalogSource(client: client))
        let refresh = Task { try? await repository.refresh() }
        await waitUntil { server.count("/export") == 1 }
        let result = await repository.observeRelatedProducts(to: "7", storeID: nil)
        let items = await publishedItems(result.map(\.items).eraseToAnyPublisher(), where: { _ in true })
        XCTAssertTrue(items.isEmpty)
        await refresh.value
        XCTAssertEqual(server.count("/analogs"), 1)
    }

    func testUnavailableAnalogEndpointUsesCachedStoreOffersAndRetriesOnReopening() async throws {
        let cache = ControlledCatalogCache()
        cache.snapshot = try CatalogFixtures.snapshot(CatalogImport(
            products: ["7", "8", "9"].map { CatalogProduct(id: $0, name: "Milk " + $0, productType: "milk") },
            stores: [CatalogStore(id: "a", name: "A"), CatalogStore(id: "b", name: "B")],
            offers: [
                CatalogOffer(id: "a8", productID: "8", storeID: "a", price: 75, currency: "RUB"),
                CatalogOffer(id: "b9", productID: "9", storeID: "b", price: 60, currency: "RUB")
            ]
        ))
        let ranked = #"[{"id":9,"name":"Milk 9","category":"Dairy","package_amount":1,"package_unit":"l","similarity":0.8,"min_price_kopecks":6000}]"#
        let (client, server) = makeClient { _, requests in
            requests.count < 3 ? .json("{}", status: 503) : .json(ranked)
        }
        let repository = DefaultCatalogRepository(cache: cache, source: APICatalogSource(client: client))
        let search = SearchViewModel(repository: repository)
        let load: (String) async -> [Product] = { await search.alternatives(for: $0, storeID: nil) }
        let firstPage = ProductDetailViewModel()
        await firstPage.loadAlternatives(for: "7", using: load)
        await firstPage.loadAlternatives(for: "7", using: load)
        XCTAssertEqual(firstPage.alternatives(for: "7").map(\.id), ["9", "8"])
        XCTAssertEqual(server.count("/analogs"), 1)
        let scoped = await search.alternatives(for: "7", storeID: "a")
        XCTAssertEqual(scoped.flatMap(\.offers).map(\.id), ["a8"])
        let reopened = ProductDetailViewModel()
        await reopened.loadAlternatives(for: "7", using: load)
        XCTAssertEqual(reopened.alternatives(for: "7").map(\.id), ["9"])
        XCTAssertEqual(server.count("/analogs"), 3)
    }

    func testPublicProductSearchEncodesQueryAndDecodesDistinctProductIDs() async throws {
        let row = #"{"id":42,"name":"Сыр","brand":null,"category":"Сыры","product_type":null,"package_amount":150.5,"package_unit":"g"}"#
        let (client, server) = makeClient { _, _ in .json("[\(row),\(row)]") }
        let query = "Сыр + 50% & хлеб"
        let matches = try await APICatalogSource(client: client).searchProducts(matching: query)
        XCTAssertEqual(matches.map(\.id), ["42"])
        XCTAssertEqual(matches.first?.packageQuantity, Decimal(string: "150.5"))
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/v1/products/search")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertTrue(components.percentEncodedQuery?.contains("%2B") == true)
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "10")])
    }

    func testPublicCatalogExportDecodesExactAmountsAndSupportsConditionalRequests() async throws {
        let (client, server) = makeClient { request, _ in
            if request.value(forHTTPHeaderField: "If-None-Match") == "\"7\"" {
                return HTTPStubReply(status: 304, headers: ["ETag": "\"7\""])
            }
            var reply = HTTPStubReply.json(CatalogAPIFixture.json)
            reply.headers["ETag"] = "\"7\""
            return reply
        }
        let source = APICatalogSource(client: client)
        guard case .snapshot(let batch) = try await source.loadCatalog(ifNoneMatch: nil) else { return XCTFail("Expected snapshot") }
        XCTAssertEqual(batch.products.first?.id, "42")
        XCTAssertEqual(batch.products.first?.packageQuantity, Decimal(string: "930.5"))
        XCTAssertEqual(batch.products.first?.packageUnit, "ml")
        XCTAssertEqual(batch.stores.first?.format, "supermarket")
        XCTAssertEqual(batch.offers.first?.offer.price, Decimal(string: "89.99"))
        XCTAssertEqual(batch.offers.first?.offer.cardPrice, Decimal(string: "79.99"))
        XCTAssertEqual(batch.offers.first?.offer.priceConditions, "With a card")
        XCTAssertEqual(batch.offers.first?.id, "7-42")
        XCTAssertEqual(batch.metadata?.etag, "\"7\"")
        XCTAssertEqual(batch.metadata?.isSynthetic, true)
        guard case .notModified = try await source.loadCatalog(ifNoneMatch: batch.metadata?.etag) else { return XCTFail("Expected 304") }
        XCTAssertEqual(server.requests.map { $0.url?.path }, ["/api/v1/catalog/export", "/api/v1/catalog/export"])
        XCTAssertEqual(server.requests.map { $0.value(forHTTPHeaderField: "If-None-Match") }, [nil, "\"7\""])
        XCTAssertTrue(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    func testGuestLoadsCatalogOnFirstLaunchAndRestoresItOffline() async throws {
        let (client, server) = makeClient { _, requests in
            requests.count == 1 ? .json(CatalogAPIFixture.json) : .failure(.notConnectedToInternet)
        }
        let cache = ControlledCatalogCache()
        let saved = expectation(description: "Guest catalog saved")
        cache.onSaved = { saved.fulfill() }
        func launch() async -> AppDependencies {
            let service = DefaultAuthenticationService(client: client, store: MemoryAuthenticationStore())
            let app = AppDependencies(cache: cache, source: APICatalogSource(client: client), authenticationService: service)
            await app.load()
            return app
        }
        let online = await launch()
        let fresh = await catalogItems(from: online.catalog)
        XCTAssertNil(online.authentication.user)
        XCTAssertEqual(fresh.map(\.id), ["42"])
        await fulfillment(of: [saved], timeout: 5)
        cache.onSaved = nil

        let offline = await launch()
        let restored = await catalogItems(from: offline.catalog)
        XCTAssertEqual(restored, fresh)
        XCTAssertEqual(server.requests.map { $0.url?.path }, ["/api/v1/catalog/export", "/api/v1/catalog/export"])
        XCTAssertTrue(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    func testFirstGuestRequestUsesReopenedSQLiteSnapshotForNotModified() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Catalog.sqlite")
        let original = CatalogFixtures.export(version: 7, date: CatalogFixtures.cachedAt)
        let seed = PersistenceController(storeURL: url)
        try await CoreDataCatalogCache(persistence: seed).save(original)
        try closeStore(seed)

        let reopened = PersistenceController(storeURL: url)
        defer { try? closeStore(reopened) }
        let cache = RecordingCatalogCache(storage: CoreDataCatalogCache(persistence: reopened))
        let saved = expectation(description: "Validation persisted")
        cache.onSaved = { saved.fulfill() }
        let (client, server) = makeClient { request, _ in
            request.value(forHTTPHeaderField: "If-None-Match") == "\"7\""
                ? HTTPStubReply(status: 304) : .json(CatalogAPIFixture.json)
        }
        let auth = DefaultAuthenticationService(client: client, store: MemoryAuthenticationStore())
        let app = AppDependencies(cache: cache, source: APICatalogSource(client: client), authenticationService: auth)
        await app.load()
        await fulfillment(of: [saved], timeout: 5)

        XCTAssertEqual(server.requests.map { $0.url?.path }, ["/api/v1/catalog/export"])
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), original.metadata?.etag)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let items = await catalogItems(from: app.catalog)
        XCTAssertEqual(items.map(\.id), ["p1"])
        XCTAssertEqual(items.first?.offers.first?.cachedAt, CatalogFixtures.cachedAt)
        XCTAssertEqual(cache.writes.count, 1)
        let write = try XCTUnwrap(cache.writes.first)
        XCTAssertFalse(write.replacesCatalog)
        XCTAssertTrue(write.products.isEmpty && write.stores.isEmpty && write.offers.isEmpty)
        XCTAssertGreaterThan(try XCTUnwrap(write.metadata?.validatedAt), CatalogFixtures.cachedAt)
    }

    func testExpiredCartRequiresSignInUntilSuccessfulLogin() async throws {
        let (client, server) = makeClient { request, history in
            switch request.url!.lastPathComponent {
            case "me": return .json(AuthFixtures.userJSON)
            case "carts":
                let count = history.filter { $0.url?.lastPathComponent == "carts" }.count
                return count == 2 ? .json("{}", status: 401) : .json("[]")
            case "refresh": return .json("{}", status: 401)
            case "login":
                let count = history.filter { $0.url?.lastPathComponent == "login" }.count
                return count == 1 ? .json("{}", status: 401) : .json(AuthFixtures.authentication)
            case "logout": return .empty
            default: return .json("{}", status: 404)
            }
        }
        let suite = "authentication-expiration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryAuthenticationStore(AuthFixtures.saved())
        func launch() -> AppDependencies {
            let service = DefaultAuthenticationService(client: client, store: store)
            return AppDependencies(cache: nil, authenticationService: service, authenticationDefaults: defaults,
                                   shoppingListService: APIShoppingListService(client: service))
        }
        let app = launch()
        await app.load()
        await waitUntil { app.shoppingList.hasResolvedCart && !app.shoppingList.isBusy }
        let oldIdentity = try XCTUnwrap(app.authentication.identity)
        XCTAssertFalse(app.authentication.requiresSignIn)

        await app.shoppingList.refresh()
        await waitUntil { app.authentication.requiresSignIn }
        XCTAssertNil(app.shoppingList.account)
        XCTAssertEqual(server.count("auth/refresh"), 1)
        await app.becameActive()
        XCTAssertTrue(app.authentication.requiresSignIn)
        let relaunched = launch()
        await relaunched.load()
        let session = relaunched.authentication
        XCTAssertTrue(session.requiresSignIn)
        do {
            try await session.signIn(email: AuthFixtures.user.email, password: "wrong", intent: .signIn, requestID: UUID())
            XCTFail("The stub rejected these credentials")
        } catch { XCTAssertEqual(AuthenticationFailure.from(error, intent: .signIn), .invalidCredentials) }
        for isHome in [true, false] {
            XCTAssertEqual(CatalogBannerContent(isHome: isHome, hasCompletedSurvey: true, status: .init(), isCacheUnavailable: false,
                                                authentication: session), .signIn)
        }

        XCTAssertEqual(CatalogBannerContent(isHome: true, hasCompletedSurvey: false, status: .init(isOffline: true),
                                            isCacheUnavailable: false, authentication: session), .offline)
        try await session.signIn(email: AuthFixtures.user.email, password: "password", intent: .signIn, requestID: UUID())
        XCTAssertEqual(CatalogBannerContent(isHome: true, hasCompletedSurvey: false, status: .init(),
                                            isCacheUnavailable: false, authentication: session), .survey)
        await session.restore(afterRejectionOf: oldIdentity.sessionID)
        XCTAssertNotNil(session.user)
        XCTAssertFalse(session.requiresSignIn)
        XCTAssertFalse(launch().authentication.requiresSignIn)
        try await session.signOut()
        await session.restore(force: true)
        XCTAssertNil(session.user)
        XCTAssertFalse(session.requiresSignIn)
    }

    func testCartRejectionDuringProfileVerificationStillPublishesExpiration() async {
        let (service, _) = makeService { request, _ in
            if request.url?.lastPathComponent == "me" { return .json(AuthFixtures.userJSON, delay: 0.2) }
            return .json("{}", status: 401)
        }
        let app = AppDependencies(cache: nil, authenticationService: service, shoppingListService: APIShoppingListService(client: service))
        await app.load()
        await waitUntil { app.authentication.requiresSignIn && !app.authentication.isVerifying }
        XCTAssertNil(app.authentication.user)
        XCTAssertNil(app.shoppingList.account)
    }

    func testPublicCatalogFailureDoesNotRefreshOrInvalidateSignedInSession() async throws {
        let (client, server) = makeClient { request, _ in
            request.url?.path == "/api/v1/users/me" ? .json(AuthFixtures.userJSON) : HTTPStubReply(status: 401)
        }
        let saved = AuthFixtures.saved()
        let store = MemoryAuthenticationStore(saved)
        let service = DefaultAuthenticationService(client: client, store: store)
        let app = AppDependencies(cache: nil, source: APICatalogSource(client: client), authenticationService: service)
        var status = CatalogStatus()
        let observation = app.catalog.status.sink { status = $0 }
        defer { observation.cancel() }
        await app.load()
        XCTAssertEqual(status.failure, .unavailable)
        XCTAssertEqual(app.authentication.identity?.sessionID, saved.id)
        XCTAssertFalse(app.authentication.requiresSignIn)
        XCTAssertEqual(store.snapshot?.tokens, saved.tokens)
        XCTAssertEqual(server.count("auth/refresh"), 0)
        XCTAssertEqual(server.count("users/me"), 1)
        let export = try XCTUnwrap(server.requests.first { $0.url?.path == "/api/v1/catalog/export" })
        XCTAssertNil(export.value(forHTTPHeaderField: "Authorization"))
    }

    func testCartAndProfileShareRefreshAndRejectResponsesAfterLogout() async throws {
        let (service, server) = makeService(store: MemoryAuthenticationStore(AuthFixtures.saved(expired: true))) { request, _ in
            if request.url!.path.hasSuffix("refresh") { return .json(AuthFixtures.rotatedTokens, delay: 0.05) }
            if request.url!.path.hasSuffix("carts") { return .json("[]", delay: 0.05) }
            return .json(AuthFixtures.userJSON)
        }
        async let user = service.currentUser()
        let carts = APIShoppingListService(client: service)
        async let cart = carts.activeCart()
        _ = try await (user, cart)
        XCTAssertEqual(server.count("auth/refresh"), 1)
        let pending = Task { try await carts.activeCart() }
        await waitUntil { server.count("carts") == 2 }
        try await service.signOut()
        do { _ = try await pending.value; XCTFail("Late cart must be rejected") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testInvalidExportCannotBeImportedAndUnexpected304IsRejected() async throws {
        for response in [HTTPStubReply.json(CatalogAPIFixture.json.replacingOccurrences(of: "\"store_id\":7", with: "\"store_id\":8")),
                         HTTPStubReply(status: 304)] {
            let (client, _) = makeClient { _, _ in response }
            do { _ = try await APICatalogSource(client: client).loadCatalog(ifNoneMatch: nil); XCTFail("Expected rejection") }
            catch { XCTAssertTrue(error is CatalogError || error is APIError) }
        }
    }

    private func makeService(store: any AuthenticationSessionStore = MemoryAuthenticationStore(AuthFixtures.saved()),
                             handler: @escaping @Sendable (URLRequest, [URLRequest]) -> HTTPStubReply)
        -> (DefaultAuthenticationService, AuthenticationHTTPStub) {
        let (client, server) = makeClient(handler: handler)
        return (DefaultAuthenticationService(client: client, store: store), server)
    }

    private func makeClient(handler: @escaping @Sendable (URLRequest, [URLRequest]) -> HTTPStubReply)
        -> (APIClient, AuthenticationHTTPStub) {
        let server = AuthenticationHTTPStub(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticationURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(baseURL: URL(string: "https://\(server.host)/api/v1/")!, session: session)
        addTeardownBlock {
            session.invalidateAndCancel()
            AuthenticationURLProtocol.unregister(server.host)
        }
        return (client, server)
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
    func cachedIdentity() async throws -> AuthenticationIdentity? { try await base.cachedIdentity() }
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

nonisolated private enum CatalogAPIFixture {
    static let json = #"{"import_id":7,"imported_at":"2026-11-08T00:00:00Z","is_synthetic":true,"offer_max_age_hours":48,"products":[{"id":42,"name":"Milk","brand":null,"category":"Dairy","product_type":"milk","package_amount":930.5,"package_unit":"ml"}],"stores":[{"id":7,"chain":"Store","name":"Nearby","address":"Street","latitude":59.9,"longitude":30.3,"format":"supermarket"}],"offers":[{"id":"7-42","product_id":42,"store_id":7,"price_kopecks":8999,"currency":"RUB","card_price_kopecks":7999,"in_stock":null,"price_type":"promo","price_conditions":"With a card","source_product_id":"source-42","source_url":"https://example.com/product","source_updated_at":"2026-11-08T00:00:00Z"}]}"#
}
