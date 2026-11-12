import Foundation

nonisolated struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: UUID
    let email: String
    let role: String
    let createdAt: Date
}

nonisolated enum AuthenticationIntent: Equatable, Sendable {
    case signIn
    case register
}

nonisolated struct AuthenticationTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    var isValid: Bool {
        !accessToken.isEmpty && !refreshToken.isEmpty && refreshToken.count <= 512 && expiresIn > 0
    }
}

nonisolated struct AuthenticationResponse: Decodable, Sendable {
    let user: AuthenticatedUser
    let tokens: AuthenticationTokens
}

/// Public session identity without credentials. Stable across token rotation and app launches.
nonisolated struct AuthenticationIdentity: Equatable, Sendable {
    let sessionID: UUID
    var user: AuthenticatedUser
}

/// A provisional response. Receiving it alone never persists or publishes an account.
nonisolated struct AuthenticationGrant: Sendable {
    let generation: UUID
    let session: StoredAuthentication
}

nonisolated struct StoredAuthentication: Codable, Equatable, Sendable {
    let id: UUID
    var user: AuthenticatedUser
    var tokens: AuthenticationTokens
    var expiresAt: Date
    var refreshPending = false

    init(id: UUID = UUID(), user: AuthenticatedUser, tokens: AuthenticationTokens, receivedAt: Date = Date()) {
        self.id = id
        self.user = user
        self.tokens = tokens
        expiresAt = receivedAt.addingTimeInterval(TimeInterval(tokens.expiresIn))
    }
}

nonisolated struct AuthenticationCredentials: Encodable, Sendable {
    let email: String
    let password: String
}

nonisolated struct RefreshCredentials: Encodable, Sendable {
    let refreshToken: String
}

nonisolated enum AuthenticationFailure: Error, Equatable, Sendable {
    case invalidEmail
    case missingPassword
    case passwordTooShort
    case passwordTooLong
    case invalidCredentials
    case emailAlreadyRegistered
    case invalidInput
    case offline
    case timedOut
    case rateLimited(until: Date?)
    case sessionExpired
    case sessionCleanupFailed
    case storage
    case unavailable

    var invalidatesSession: Bool {
        self == .sessionExpired || self == .sessionCleanupFailed
    }

    static func from(_ error: Error, intent: AuthenticationIntent? = nil) -> Self {
        if let failure = error as? Self { return failure }
        if error is AuthenticationStorageError { return .storage }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .offline
            case .timedOut: return .timedOut
            default: return .unavailable
            }
        }
        guard let error = error as? APIError else { return .unavailable }
        switch error.status {
        case 401: return intent == nil ? .sessionExpired : .invalidCredentials
        case 409 where intent == .register: return .emailAlreadyRegistered
        case 422: return .invalidInput
        case 429: return .rateLimited(until: error.retryAfter)
        default: return .unavailable
        }
    }
}
