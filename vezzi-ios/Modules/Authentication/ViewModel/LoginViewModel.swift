import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case failure(Failure)
        case success
    }

    enum Failure: Equatable {
        case invalidEmail
        case missingPassword
        case unavailable
    }

    struct Request: Equatable {
        let id = UUID()
        let email: String
        let password: String
        let intent: AuthenticationIntent
    }

    @Published var email = "" {
        didSet {
            if email != oldValue { clearFailure(.invalidEmail) }
        }
    }
    @Published var password = "" {
        didSet {
            if password != oldValue { clearFailure(.missingPassword) }
        }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var request: Request?

    var isBusy: Bool { phase == .loading || phase == .success }

    nonisolated deinit {}

    func submit(_ intent: AuthenticationIntent) {
        guard !isBusy else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            phase = .failure(.invalidEmail)
            return
        }
        guard !password.isEmpty else {
            phase = .failure(.missingPassword)
            return
        }
        phase = .loading
        request = Request(email: email, password: password, intent: intent)
    }

    /// Called from the view's task so dismissal cancels both the request and the success hold.
    func authenticate(using session: AuthenticationSession, successDuration: Duration) async {
        guard let request, phase == .loading else { return }
        do {
            let user = try await session.service.authenticate(email: request.email, password: request.password,
                                                              intent: request.intent)
            try Task.checkCancellation()
            guard self.request?.id == request.id else { return }
            phase = .success
            try await Task.sleep(for: successDuration)
            try Task.checkCancellation()
            guard self.request?.id == request.id else { return }
            self.request = nil
            password = ""
            session.signIn(as: user)
        } catch is CancellationError {
            if self.request?.id == request.id { cancel() }
        } catch {
            guard !Task.isCancelled, self.request?.id == request.id else { return }
            self.request = nil
            phase = .failure(.unavailable)
        }
    }

    func cancel() {
        request = nil
        password = ""
        phase = .idle
    }

    private func clearFailure(_ expected: Failure) {
        guard case .failure(let failure) = phase, failure == expected || failure == .unavailable else { return }
        phase = .idle
    }

    private static func isValidEmail(_ value: String) -> Bool {
        // Deliberately limited to everyday addresses; the server will own definitive validation.
        let pattern = #"^[A-Z0-9a-z!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Z0-9a-z!#$%&'*+/=?^_`{|}~-]+)*@[A-Z0-9a-z](?:[A-Z0-9a-z-]*[A-Z0-9a-z])?(?:\.[A-Z0-9a-z](?:[A-Z0-9a-z-]*[A-Z0-9a-z])?)+$"#
        return value.utf8.count <= 254 && value.range(of: pattern, options: .regularExpression) != nil
    }
}
