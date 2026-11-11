import Foundation

/// Talks to the Schedule Bridge API.
///
/// Signed-in calls send the access token (15 minutes) and, on a 401, refresh once and retry.
/// Refresh tokens rotate and presenting a used one revokes the whole session, so concurrent
/// 401s share a single refresh instead of each spending the same token.
actor APIClient {
    nonisolated let baseURL: URL
    private let session: URLSession
    private let tokens: any TokenStore
    private var refreshTask: Task<AuthTokens, Error>?

    init(baseURL: URL, tokens: any TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
    }

    nonisolated var hasSession: Bool { tokens.load() != nil }

    // MARK: Sessions

    /// Signs in with email and password and keeps the tokens.
    /// Throws `.http(403, code: "email_not_confirmed")` until the email link has been used.
    @discardableResult
    func signIn(email: String, password: String) async throws -> AuthTokens {
        let result = try await perform(API.login(email: email, password: password), token: nil)
        tokens.save(result)
        return result
    }

    /// Signs in with a Google ID token (from Google Sign-In) and keeps the tokens.
    @discardableResult
    func signIn(googleIdToken: String) async throws -> AuthTokens {
        let result = try await perform(API.google(idToken: googleIdToken), token: nil)
        tokens.save(result)
        return result
    }

    /// Revokes the session on the server when possible and always forgets it locally.
    func signOut() async {
        guard let current = tokens.load() else { return }
        tokens.clear()
        _ = try? await perform(API.logout(refreshToken: current.refreshToken), token: nil)
    }

    // MARK: Requests

    func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        guard endpoint.requiresAuth else { return try await perform(endpoint, token: nil) }
        guard let current = tokens.load() else { throw APIError.signedOut }

        do {
            return try await perform(endpoint, token: current.accessToken)
        } catch let error as APIError where error.status == 401 {
            let renewed = try await refreshedTokens(replacing: current)
            return try await perform(endpoint, token: renewed.accessToken)
        }
    }

    private func refreshedTokens(replacing stale: AuthTokens) async throws -> AuthTokens {
        if let refreshTask { return try await refreshTask.value }
        // Another request may have finished refreshing while this one was in flight.
        if let latest = tokens.load(), latest.refreshToken != stale.refreshToken { return latest }
        guard tokens.load() != nil else { throw APIError.signedOut }

        let task = Task { try await performRefresh(stale.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh(_ refreshToken: String) async throws -> AuthTokens {
        do {
            let renewed = try await perform(API.refresh(refreshToken: refreshToken), token: nil)
            tokens.save(renewed)
            return renewed
        } catch let error as APIError where error.status.map({ (400..<500).contains($0) && $0 != 429 }) ?? false {
            // Expired, revoked or reused: the session is over. Network errors keep the tokens for a retry.
            tokens.clear()
            throw APIError.signedOut
        }
    }

    private func perform<Response>(_ endpoint: Endpoint<Response>, token: String?) async throws -> Response {
        var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        if !endpoint.query.isEmpty { components.queryItems = endpoint.query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let problem = (try? JSONDecoder().decode(Problem.self, from: data)) ?? Problem()
            throw APIError.http(status: http.statusCode, problem: problem)
        }

        if Response.self == NoContent.self, data.isEmpty { return NoContent() as! Response }
        do {
            return try APIClient.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    // MARK: JSON

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = APIDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
            }
            return date
        }
        return decoder
    }()
}

enum APIDate {
    /// Parses the API's ISO 8601 timestamps. .NET writes up to 7 fractional digits,
    /// which ISO8601DateFormatter rejects, so they're cut to milliseconds first.
    static func parse(_ text: String) -> Date? {
        let trimmed = text.replacing(/(\.\d{3})\d+/) { $0.output.1 }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: trimmed) ?? ISO8601DateFormatter().date(from: trimmed)
    }
}
