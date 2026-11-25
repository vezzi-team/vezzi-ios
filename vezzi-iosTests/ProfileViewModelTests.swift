import Foundation
import XCTest
@testable import vezzi_ios

@MainActor
final class ProfileViewModelTests: XCTestCase {
    func testShoppingDefaultSurvivesRestartAndStaysWithItsAccount() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AuthenticationSession(service: ProfileAccountFixture())
        let preferences = ShoppingPreferences(authentication: account, defaults: defaults)
        await account.restore()
        let accountID = try XCTUnwrap(account.user?.id)
        XCTAssertEqual(preferences.mode, .cheaper)
        preferences.save(.faster, for: accountID)
        let restored = ShoppingPreferences(authentication: account, defaults: defaults)
        XCTAssertEqual(restored.mode, .faster)

        let otherAccount = AuthenticationSession(service: ProfileAccountFixture())
        await otherAccount.restore()
        let other = ShoppingPreferences(authentication: otherAccount, defaults: defaults)
        other.save(.faster, for: accountID)
        XCTAssertEqual(other.mode, .cheaper)
        try await account.signOut()
        XCTAssertEqual(restored.mode, .cheaper)
        restored.save(.faster, for: accountID)
        XCTAssertEqual(restored.mode, .cheaper)
    }

    func testFailedLogoutRetainsAccountAndReportsError() async {
        let session = AuthenticationSession(service: ProfileAccountFixture(failSignOut: true))
        await session.restore()
        let draft = ProfileViewModel(session: session)
        await draft.signOut()
        XCTAssertNotNil(session.user)
        XCTAssertTrue(draft.showsSignOutError)
        XCTAssertFalse(draft.isSigningOut)
    }

    func testCompletingSurveyIsAccountScopedAndIndependentOfManualPreference() async throws {
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = AuthenticationSession(service: ProfileAccountFixture())
        let preferences = ShoppingPreferences(authentication: session, defaults: defaults)
        await session.restore()
        let id = try XCTUnwrap(session.user?.id)
        preferences.save(.faster, for: id)
        XCTAssertFalse(preferences.hasCompletedSurvey)
        preferences.completeSurvey(with: .faster, for: id)
        XCTAssertTrue(ShoppingPreferences(authentication: session, defaults: defaults).hasCompletedSurvey)
        try await session.signOut()
        preferences.completeSurvey(with: .cheaper, for: id)
        XCTAssertFalse(preferences.hasCompletedSurvey)
    }

    func testProfileSheetPreservesTabHistories() {
        let router = AppRouter()
        router.push(.profile, in: .home)
        router.push(.profileData, in: .home)
        router.selectTab(.search)
        router.presentProfile(.settings)
        XCTAssertEqual(router.presentedSheet, .profile(.settings))
        router.dismissSheet()
        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(router.path(in: .home), [.profile, .profileData])
        XCTAssertTrue(router.path(in: .search).isEmpty)
        router.selectTab(.home)
        XCTAssertEqual(router.path(in: .home).count, 2)
    }
}

/// Credential-free fixture: never calls the production authentication service.
actor ProfileAccountFixture: AuthenticationService {
    private var identity: AuthenticationIdentity?
    private let failSignOut: Bool

    init(failSignOut: Bool = false) {
        self.failSignOut = failSignOut
        identity = AuthenticationIdentity(sessionID: UUID(), user: AuthenticatedUser(
            id: UUID(), email: "profile-test@example.invalid", role: "user", createdAt: Date()
        ))
    }

    func authenticate(email: String, password: String, intent: AuthenticationIntent) throws -> AuthenticationGrant {
        throw AuthenticationFailure.unavailable
    }
    func commit(_ grant: AuthenticationGrant) throws -> AuthenticatedUser { throw AuthenticationFailure.unavailable }
    func discard(_ grant: AuthenticationGrant) { }
    func cachedIdentity() -> AuthenticationIdentity? { identity }
    func currentUser() throws -> AuthenticatedUser {
        guard let user = identity?.user else { throw AuthenticationFailure.sessionExpired }
        return user
    }
    func signOut() throws {
        if failSignOut { throw AuthenticationFailure.storage }
        identity = nil
    }
}
