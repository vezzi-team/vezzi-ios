import Combine
import UIKit
import XCTest
@testable import vezzi_ios

@MainActor
final class LoginViewModelTests: XCTestCase {
    func testInvalidEmailNeverCreatesARequestAndEditingClearsTheError() {
        let model = LoginViewModel()
        model.password = "  mock password  "
        for email in ["", "name", "name@", "name@example", "name@.com", "a b@example.com", "a..b@example.com"] {
            model.email = email
            model.submit(.signIn)
            XCTAssertEqual(model.phase, .failure(.invalidEmail), email)
            XCTAssertNil(model.request)
            model.email = email
            XCTAssertEqual(model.phase, .failure(.invalidEmail), "Focus updates must not clear an unchanged value's error")
        }
        model.email = "name@example.com"
        XCTAssertEqual(model.phase, .idle)
    }

    func testSignInTrimsEmailAndPreventsDuplicateSubmissions() async {
        let service = ImmediateService()
        let session = AuthenticationSession(service: service)
        let model = LoginViewModel()
        model.password = "  mock password  "
        model.email = "  moti+test@example.com \n"
        model.submit(.signIn)
        let request = model.request
        model.submit(.register)
        XCTAssertEqual(model.request, request)
        XCTAssertEqual(model.phase, .loading)

        await model.authenticate(using: session, successDuration: .zero)

        XCTAssertEqual(service.intents, [.signIn])
        XCTAssertEqual(service.receivedPasswords, ["  mock password  "])
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertNil(model.request)
        XCTAssertEqual(session.user?.email, "moti+test@example.com")
        XCTAssertEqual(model.phase, .success)
    }

    func testServiceFailureCanBeRetriedAsRegistration() async {
        let service = ImmediateService()
        service.shouldFail = true
        let session = AuthenticationSession(service: service)
        let model = LoginViewModel()
        model.password = "  mock password  "
        model.email = "moti@example.com"
        model.submit(.signIn)
        await model.authenticate(using: session, successDuration: .zero)
        XCTAssertEqual(model.phase, .failure(.offline))
        XCTAssertNil(session.user)

        service.shouldFail = false
        model.submit(.register)
        await model.authenticate(using: session, successDuration: .zero)
        XCTAssertEqual(service.intents, [.signIn, .register])
        XCTAssertEqual(session.user?.email, model.email)
    }

    func testDismissalIgnoresAnUncooperativeLateResponse() async {
        let started = expectation(description: "Authentication started")
        let service = SuspendedService(started: started)
        let session = AuthenticationSession(service: service)
        let model = LoginViewModel()
        model.password = "  mock password  "
        model.email = "moti@example.com"
        model.submit(.signIn)
        let task = Task { await model.authenticate(using: session, successDuration: .zero) }
        await fulfillment(of: [started], timeout: 1)

        model.cancel(using: session)
        service.continuation?.resume(returning: testGrant(email: model.email))
        await task.value
        XCTAssertNil(session.user)
        XCTAssertEqual(model.phase, .idle)
    }

    func testTaskCancellationNeverSignsIn() async {
        let started = expectation(description: "Authentication started")
        let service = SuspendedService(started: started)
        let session = AuthenticationSession(service: service)
        let model = LoginViewModel()
        model.password = "  mock password  "
        model.email = "moti@example.com"
        model.submit(.signIn)
        let task = Task { await model.authenticate(using: session, successDuration: .zero) }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()
        service.continuation?.resume(returning: testGrant(email: model.email))
        await task.value
        XCTAssertNil(session.user)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertNil(model.request)
    }

    func testSignOutClearsAccountPreferences() async throws {
        let session = AuthenticationSession(service: ImmediateService())
        try await session.signIn(email: "moti@example.com", password: "password", intent: .signIn, requestID: UUID())
        session.preferences.priority = .price
        session.preferences.notificationsEnabled = false
        try await session.signOut()
        XCTAssertNil(session.user)
        XCTAssertEqual(session.preferences.priority, .balanced)
        XCTAssertTrue(session.preferences.notificationsEnabled)
    }

    func testMissingPasswordDoesNotStartARequestAndOnlyPasswordEditingClearsItsError() {
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.submit(.signIn)
        XCTAssertEqual(model.phase, .failure(.missingPassword))
        XCTAssertNil(model.request)

        model.password = ""
        XCTAssertEqual(model.phase, .failure(.missingPassword))

        model.email = "other@example.com"
        XCTAssertEqual(model.phase, .failure(.missingPassword))
        model.password = "mock password"
        XCTAssertEqual(model.phase, .idle)
    }

    func testClosingSuccessConfirmationKeepsTheAlreadyCommittedAccount() async {
        let session = AuthenticationSession(service: ImmediateService())
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.password = "mock password"
        model.submit(.signIn)
        let succeeded = expectation(description: "Success confirmation is displayed")
        let subscription = model.$phase.sink { phase in
            if phase == .success { succeeded.fulfill() }
        }
        let task = Task { await model.authenticate(using: session, successDuration: .seconds(60)) }
        await fulfillment(of: [succeeded], timeout: 1)
        model.cancel(using: session)
        task.cancel()
        await task.value
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(session.user?.email, "moti@example.com")
        XCTAssertNil(model.request)
        XCTAssertTrue(model.password.isEmpty)
    }

    func testRegistrationAndLoginUseDifferentPasswordLimits() {
        let model = LoginViewModel()
        model.email = "moti@example.com"
        model.password = "short"
        model.submit(.register)
        XCTAssertEqual(model.phase, .failure(.passwordTooShort))
        XCTAssertNil(model.request)
        model.submit(.signIn)
        XCTAssertEqual(model.phase, .loading)
        let other = LoginViewModel()
        other.email = model.email
        other.password = String(repeating: "a", count: 129)
        other.submit(.signIn)
        XCTAssertEqual(other.phase, .failure(.passwordTooLong))
        other.password = String(repeating: "a", count: 128)
        other.submit(.register)
        XCTAssertEqual(other.phase, .loading)
    }

    func testMascotMorphsKeepMatchingPathTopologyAcrossEveryPose() throws {
        XCTAssertNotNil(UIImage.Brand.motiYarn?.cgImage)
        for part in MotiFaceGeometry.Part.allCases {
            var reference: [CGPathElementType]?
            for state in MotiMascotView.State.allCases {
                let motion = MotiMotion(state: state)
                XCTAssertGreaterThan(motion.duration, 0)
                XCTAssertEqual(motion.frames.first?.time, 0)
                for frame in motion.frames {
                    let path = MotiFaceGeometry.path(for: part, pose: frame.pose)
                    var elements: [CGPathElementType] = []
                    path.applyWithBlock { elements.append($0.pointee.type) }
                    XCTAssertFalse(elements.isEmpty)
                    if let reference { XCTAssertEqual(elements, reference, "\(state): \(part)") }
                    else { reference = elements }
                    let opacity = MotiFaceGeometry.opacity(for: part, pose: frame.pose)
                    XCTAssertTrue((0...1).contains(opacity))
                    XCTAssertTrue(path.boundingBoxOfPath.origin.x.isFinite)
                    XCTAssertTrue(path.boundingBoxOfPath.origin.y.isFinite)
                }
            }
        }
    }

    func testMascotCyclesReturnToTheirRestingGeometryWithoutAJump() throws {
        for state in MotiMascotView.State.allCases {
            let motion = MotiMotion(state: state)
            let last = try XCTUnwrap(motion.frames.last).pose
            for part in MotiFaceGeometry.Part.allCases {
                XCTAssertEqual(MotiFaceGeometry.path(for: part, pose: motion.restingPose),
                               MotiFaceGeometry.path(for: part, pose: last))
                XCTAssertEqual(MotiFaceGeometry.opacity(for: part, pose: motion.restingPose),
                               MotiFaceGeometry.opacity(for: part, pose: last))
            }
            XCTAssertEqual(motion.restingPose.lift, last.lift)
            XCTAssertEqual(motion.restingPose.tilt, last.tilt)
            XCTAssertEqual(motion.restingPose.stretch, last.stretch)
            XCTAssertEqual(motion.repeats, state != .error && state != .success)
            XCTAssertTrue(zip(motion.frames, motion.frames.dropFirst()).allSatisfy { $0.time < $1.time })
        }
    }

}

@MainActor
private final class ImmediateService: TestAuthenticationService {
    var intents: [AuthenticationIntent] = []
    var receivedPasswords: [String] = []
    var shouldFail = false

    @MainActor func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        intents.append(intent)
        receivedPasswords.append(password)
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return testGrant(email: email)
    }
}

@MainActor
private final class SuspendedService: TestAuthenticationService {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<AuthenticationGrant, Error>?

    init(started: XCTestExpectation) { self.started = started }

    @MainActor func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticationGrant {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
}

@MainActor
private protocol TestAuthenticationService: AuthenticationService { }

extension TestAuthenticationService {
    func commit(_ grant: AuthenticationGrant) async throws -> AuthenticatedUser {
        try Task.checkCancellation()
        return grant.session.user
    }
    func discard(_ grant: AuthenticationGrant) async throws { }
    func cachedIdentity() async throws -> AuthenticationIdentity? { nil }
    func currentUser() async throws -> AuthenticatedUser { throw AuthenticationFailure.sessionExpired }
    func signOut() async throws { }
}

@MainActor
private func testGrant(email: String) -> AuthenticationGrant {
    AuthenticationGrant(generation: UUID(), session: StoredAuthentication(
        user: AuthenticatedUser(id: UUID(), email: email, role: "user", createdAt: Date()),
        tokens: AuthenticationTokens(accessToken: "access", refreshToken: "refresh", expiresIn: 1800)
    ))
}
