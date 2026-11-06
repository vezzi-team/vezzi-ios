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
        XCTAssertEqual(model.phase, .failure(.unavailable))
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

        model.cancel()
        service.continuation?.resume(returning: AuthenticatedUser(email: model.email))
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
        service.continuation?.resume(returning: AuthenticatedUser(email: model.email))
        await task.value
        XCTAssertNil(session.user)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.password.isEmpty)
        XCTAssertNil(model.request)
    }

    func testSignOutClearsAccountPreferences() {
        let session = AuthenticationSession()
        session.signIn(as: AuthenticatedUser(email: "moti@example.com"))
        session.preferences.priority = .price
        session.preferences.notificationsEnabled = false
        session.signOut()
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

    func testCancelDuringSuccessConfirmationNeverCommitsTheAccount() async {
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
        model.cancel()
        task.cancel()
        await task.value
        withExtendedLifetime(subscription) {}
        XCTAssertNil(session.user)
        XCTAssertNil(model.request)
        XCTAssertTrue(model.password.isEmpty)
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
private final class ImmediateService: AuthenticationService {
    var intents: [AuthenticationIntent] = []
    var receivedPasswords: [String] = []
    var shouldFail = false

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticatedUser {
        intents.append(intent)
        receivedPasswords.append(password)
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return AuthenticatedUser(email: email)
    }
}

@MainActor
private final class SuspendedService: AuthenticationService {
    let started: XCTestExpectation
    var continuation: CheckedContinuation<AuthenticatedUser, Error>?

    init(started: XCTestExpectation) { self.started = started }

    func authenticate(email: String, password: String, intent: AuthenticationIntent) async throws -> AuthenticatedUser {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
}
