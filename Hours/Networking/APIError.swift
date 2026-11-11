import Foundation

/// RFC 9110 ProblemDetails, as the API returns for every error.
struct Problem: Decodable, Equatable, Sendable {
    var title: String?
    var detail: String?
    /// Machine-readable reason, e.g. "email_not_confirmed".
    var code: String?
    /// Field validation errors, keyed by field name.
    var errors: [String: [String]]?
}

enum APIError: Error, Equatable, Sendable {
    /// No session, or the refresh token was rejected. The user has to sign in again.
    case signedOut
    /// The API answered with a non-2xx status.
    case http(status: Int, problem: Problem)
    /// The request never got an answer (offline, timeout, DNS, TLS).
    case transport(String)
    /// The answer wasn't the JSON we expected.
    case decoding(String)

    var status: Int? {
        if case let .http(status, _) = self { status } else { nil }
    }

    var code: String? {
        if case let .http(_, problem) = self { problem.code } else { nil }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .signedOut:
            "You've been signed out. Sign in again."
        case let .http(status, problem):
            if status == 429 { "Too many attempts. Wait a minute and try again." }
            else if let fields = problem.errors, let first = fields.values.first?.first { first }
            else { problem.detail ?? problem.title ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized }
        case let .transport(message):
            "Couldn't reach the server. \(message)"
        case .decoding:
            "The server sent something unexpected."
        }
    }
}
