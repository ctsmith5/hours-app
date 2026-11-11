import Foundation

/// One API call: where it goes, what it sends, and what it decodes to.
struct Endpoint<Response: Decodable & Sendable>: Sendable {
    enum Method: String, Sendable { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    var method: Method
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)?
    /// Signed-in calls carry the access token and refresh it once on a 401.
    var requiresAuth: Bool

    static func get(_ path: String, query: [URLQueryItem] = [], auth: Bool = true) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, body: nil, requiresAuth: auth)
    }

    static func post(_ path: String, body: (any Encodable & Sendable)?, auth: Bool) -> Endpoint {
        Endpoint(method: .post, path: path, body: body, requiresAuth: auth)
    }
}

/// Every endpoint the app uses. Mirrors the API's routes under /api/v1.
enum API {
    // MARK: Account (anonymous, rate limited per client)

    static func register(email: String, password: String) -> Endpoint<MessageResponse> {
        .post("/api/v1/auth/register", body: CredentialsBody(email: email, password: password), auth: false)
    }

    static func confirmEmail(userId: String, code: String) -> Endpoint<MessageResponse> {
        .post("/api/v1/auth/confirm-email", body: ConfirmEmailBody(userId: userId, code: code), auth: false)
    }

    static func resendConfirmation(email: String) -> Endpoint<MessageResponse> {
        .post("/api/v1/auth/resend-confirmation", body: EmailBody(email: email), auth: false)
    }

    static func login(email: String, password: String, shopId: String? = nil) -> Endpoint<AuthTokens> {
        .post("/api/v1/auth/login", body: CredentialsBody(email: email, password: password, shopId: shopId), auth: false)
    }

    static func google(idToken: String, shopId: String? = nil) -> Endpoint<AuthTokens> {
        .post("/api/v1/auth/google", body: GoogleBody(idToken: idToken, shopId: shopId), auth: false)
    }

    static func refresh(refreshToken: String, shopId: String? = nil) -> Endpoint<AuthTokens> {
        .post("/api/v1/auth/refresh", body: RefreshBody(refreshToken: refreshToken, shopId: shopId), auth: false)
    }

    static func logout(refreshToken: String) -> Endpoint<NoContent> {
        .post("/api/v1/auth/logout", body: RefreshBody(refreshToken: refreshToken), auth: false)
    }

    static func forgotPassword(email: String) -> Endpoint<MessageResponse> {
        .post("/api/v1/auth/forgot-password", body: EmailBody(email: email), auth: false)
    }

    static func resetPassword(email: String, code: String, newPassword: String) -> Endpoint<MessageResponse> {
        .post("/api/v1/auth/reset-password", body: ResetPasswordBody(email: email, code: code, newPassword: newPassword), auth: false)
    }

    // MARK: Signed in

    static func me() -> Endpoint<Me> { .get("/api/v1/me") }

    /// `day` is `YYYY-MM-DD` in the shop's time zone.
    static func appointments(on day: String) -> Endpoint<BookerList> {
        .get("/api/v1/appointments", query: [URLQueryItem(name: "date", value: day)])
    }

    static func breaks(on day: String) -> Endpoint<BookerList> {
        .get("/api/v1/breaks", query: [URLQueryItem(name: "date", value: day)])
    }

    static func services() -> Endpoint<BookerList> { .get("/api/v1/services") }

    static func defaultSchedule() -> Endpoint<JSONValue> { .get("/api/v1/schedule/default") }
}
