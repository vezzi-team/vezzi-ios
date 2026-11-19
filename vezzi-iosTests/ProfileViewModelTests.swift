import Foundation
import XCTest
@testable import vezzi_ios

@MainActor
final class ProfileViewModelTests: XCTestCase {
    func testDiscardedAddressDraftDoesNotChangeSession() {
        let session = AuthenticationSession.preview()
        let draft = ProfileViewModel(session: session)
        draft.updateAddress(ProfileAddress(title: "Home", street: "Example Street, 1"))
        XCTAssertEqual(draft.addresses.count, 1)
        XCTAssertTrue(session.preferences.addresses.isEmpty)
        let reopened = ProfileViewModel(session: session)
        XCTAssertTrue(reopened.addresses.isEmpty)
    }

    func testSavingAddressTrimsValuesAndEditingKeepsIdentity() {
        let session = AuthenticationSession.preview()
        let draft = ProfileViewModel(session: session)
        let address = ProfileAddress(title: " Home \n", street: " Example Street, 1 ")
        draft.updateAddress(address)
        XCTAssertTrue(draft.saveAddresses())
        XCTAssertEqual(session.preferences.addresses.first?.title, "Home")
        XCTAssertEqual(session.preferences.address, "Example Street, 1")
        var updated = address
        updated.street = "Example Street, 2"
        draft.updateAddress(updated)
        XCTAssertTrue(draft.saveAddresses())
        XCTAssertEqual(session.preferences.addresses.count, 1)
        XCTAssertEqual(session.preferences.addresses.first?.id, address.id)
        XCTAssertEqual(session.preferences.address, "Example Street, 2")
    }

    func testBlankAddressIsRejected() {
        let session = AuthenticationSession.preview()
        let draft = ProfileViewModel(session: session)
        draft.updateAddress(ProfileAddress(title: " \n", street: "Street"))
        draft.updateAddress(ProfileAddress(title: "Home", street: " \n"))
        XCTAssertTrue(draft.addresses.isEmpty)
    }

    func testPrioritySaveDoesNotOverwriteNewNotificationPreferences() {
        let session = AuthenticationSession.preview()
        let draft = ProfileViewModel(session: session)
        draft.priority = .price
        XCTAssertEqual(session.preferences.priority, .balanced)
        session.preferences.nearbyOffersEnabled = false
        XCTAssertTrue(draft.savePriority())
        XCTAssertEqual(session.preferences.priority, .price)
        XCTAssertFalse(session.preferences.nearbyOffersEnabled)
    }

    func testSuccessfulLogoutClearsPreferencesAndRejectsOldDraft() async {
        let session = AuthenticationSession(service: ProfileAccountFixture())
        await session.restore()
        XCTAssertNotNil(session.user)
        session.preferences.nearbyOffersEnabled = false
        let draft = ProfileViewModel(session: session)
        draft.priority = .price
        await draft.signOut()
        XCTAssertNil(session.user)
        XCTAssertFalse(draft.showsSignOutError)
        XCTAssertTrue(session.preferences.nearbyOffersEnabled)
        XCTAssertFalse(draft.savePriority())
        XCTAssertEqual(session.preferences.priority, .balanced)
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

    func testProfileSheetPreservesTabHistories() {
        let router = AppRouter()
        router.push(.profile, in: .home)
        router.push(.profileDetails(.personalDetails), in: .home)
        router.selectTab(.search)
        router.presentProfile(.notifications)
        XCTAssertEqual(router.presentedSheet, .profile(.notifications))
        router.dismissSheet()
        XCTAssertNil(router.presentedSheet)
        XCTAssertEqual(router.path(in: .home), [.profile, .profileDetails(.personalDetails)])
        XCTAssertTrue(router.path(in: .search).isEmpty)
        router.selectTab(.home)
        XCTAssertEqual(router.path(in: .home).count, 2)
    }
}

/// Credential-free fixture: never calls the production authentication service.
private actor ProfileAccountFixture: AuthenticationService {
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
