import Foundation

nonisolated enum APIConfiguration {
    static let baseURL = URL(string: "https://vezzi.vps.webdock.cloud/api/v1/")!
}

nonisolated struct APIRequest: Sendable {
    let path: String
    var method = "GET"
    var body: Data?
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
}

nonisolated struct APIResponse: Sendable {
    let data: Data
    let status: Int
    let etag: String?

    func decode<Value: Decodable & Sendable>(_ type: Value.Type = Value.self) throws -> Value {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch { throw APIError.invalidResponse }
    }
}

/// Uses the existing session owner, including single-flight token rotation.
nonisolated protocol AuthorizedRequestPerforming: Sendable {
    func authorizedResponse(for request: APIRequest) async throws -> APIResponse
}

/// HTTP transport only. Session ownership and token refresh belong to the authentication service.
nonisolated struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL = APIConfiguration.baseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
        }
    }

    func send<Response: Decodable & Sendable>(
        _ path: String, method: String = "GET", body: Data? = nil, accessToken: String? = nil
    ) async throws -> Response {
        try await response(for: APIRequest(path: path, method: method, body: body), accessToken: accessToken).decode()
    }

    func sendWithoutResponse(_ path: String, method: String, body: Data? = nil) async throws {
        _ = try await response(for: APIRequest(path: path, method: method, body: body))
    }

    static func encode<Body: Encodable>(_ body: Body) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    func response(for input: APIRequest, accessToken: String? = nil) async throws -> APIResponse {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(input.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        if !input.queryItems.isEmpty { components.queryItems = input.queryItems }
        guard let url = components.url else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = input.method
        request.httpBody = input.body
        for (name, value) in input.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if input.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(response.statusCode) || response.statusCode == 304 else {
            // Do not retain or log response bodies: validation errors can echo submitted passwords.
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
            throw APIError.http(status: response.statusCode, code: payload?.code,
                                requestID: payload?.request_id ?? response.value(forHTTPHeaderField: "X-Request-ID"),
                                retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        }
        return APIResponse(data: data, status: response.statusCode, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    private static func retryAfter(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return Date().addingTimeInterval(min(seconds, 86_400))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    private struct ErrorPayload: Decodable {
        let code: String?
        let request_id: String?
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            // Credentials and tokens must never be replayed to a redirect destination.
            completionHandler(nil)
        }
    }
}

nonisolated enum APIError: Error, Equatable, Sendable {
    case invalidResponse
    case http(status: Int, code: String?, requestID: String?, retryAfter: Date?)

    var status: Int? {
        if case .http(let status, _, _, _) = self { return status }
        return nil
    }

    var retryAfter: Date? {
        if case .http(_, _, _, let retryAfter) = self { return retryAfter }
        return nil
    }
}
