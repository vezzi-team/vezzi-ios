import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case failure(AuthenticationFailure)
        case success
    }

    struct Request: Equatable {
        let id = UUID()
        let email: String
        let password: String
        let intent: AuthenticationIntent
    }

    @Published var email = "" {
        didSet { if email != oldValue { clearFailure(editingEmail: true) } }
    }
    @Published var password = "" {
        didSet { if password != oldValue { clearFailure(editingEmail: false) } }
    }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var request: Request?
    @Published private(set) var didComplete = false

    var isBusy: Bool { phase == .loading || phase == .success }

    var emailError: String? {
        guard case .failure(let failure) = phase,
              failure == .invalidEmail || failure == .emailAlreadyRegistered else { return nil }
        return failure.message
    }

    var passwordError: String? {
        guard case .failure(let failure) = phase,
              [.missingPassword, .passwordTooShort, .passwordTooLong].contains(failure) else { return nil }
        return failure.message
    }

    var formError: String? {
        guard case .failure(let failure) = phase, emailError == nil, passwordError == nil else { return nil }
        return failure.message
    }

    nonisolated deinit {}

    func submit(_ intent: AuthenticationIntent) {
        guard !isBusy else { return }
        if case .failure(.rateLimited(let until)) = phase, let until, until > Date() { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else { phase = .failure(.invalidEmail); return }
        guard !password.isEmpty else { phase = .failure(.missingPassword); return }
        let length = password.unicodeScalars.count
        guard length <= 128 else { phase = .failure(.passwordTooLong); return }
        guard intent != .register || length >= 8 else { phase = .failure(.passwordTooShort); return }
        didComplete = false
        phase = .loading
        request = Request(email: email, password: password, intent: intent)
    }

    /// The task owns the attempt; a successful session is committed before its visual confirmation.
    func authenticate(using session: AuthenticationSession, successDuration: Duration) async {
        guard let request, phase == .loading else { return }
        do {
            try await session.signIn(email: request.email, password: request.password, intent: request.intent, requestID: request.id)
            try Task.checkCancellation()
            guard self.request?.id == request.id else { return }
            password = ""
            phase = .success
            try await Task.sleep(for: successDuration)
            try Task.checkCancellation()
            guard self.request?.id == request.id else { return }
            self.request = nil
            didComplete = true
        } catch is CancellationError {
            if self.request?.id == request.id { cancel(using: session) }
        } catch {
            guard !Task.isCancelled, self.request?.id == request.id else { return }
            self.request = nil
            phase = .failure(AuthenticationFailure.from(error, intent: request.intent))
        }
    }

    func cancel(using session: AuthenticationSession) {
        session.cancelSignIn(requestID: request?.id)
        request = nil
        password = ""
        phase = .idle
        didComplete = false
    }

    private func clearFailure(editingEmail: Bool) {
        guard case .failure(let failure) = phase else { return }
        switch failure {
        case .invalidEmail, .emailAlreadyRegistered: guard editingEmail else { return }
        case .missingPassword, .passwordTooShort, .passwordTooLong: guard !editingEmail else { return }
        case .rateLimited(let until): if let until, until > Date() { return }
        default: break
        }
        phase = .idle
    }

    private static func isValidEmail(_ value: String) -> Bool {
        // The backend owns definitive validation, including international email addresses.
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard value.utf8.count <= 254, parts.count == 2,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        return parts.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".") && !$0.contains("..") }
            && parts[1].contains(".")
    }
}
