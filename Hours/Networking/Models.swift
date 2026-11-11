import Foundation

// Shapes returned by the Schedule Bridge API (/api/v1). Property names match the API's camelCase JSON.

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let shopId: String?
    let shops: [ShopAccess]
}

struct ShopAccess: Codable, Equatable, Sendable, Identifiable {
    let shopId: String
    let shopName: String
    let employeeId: Int
    let role: String

    var id: String { shopId }
}

/// `currentShop` is nil until the account has been granted access to a shop.
struct Me: Decodable, Equatable, Sendable {
    let userId: String
    let email: String
    let displayName: String?
    let shops: [ShopAccess]
    let currentShop: CurrentShop?
}

struct CurrentShop: Decodable, Equatable, Sendable {
    let shopId: String
    let shopName: String
    /// IANA time zone, e.g. "America/New_York". Days and times are shown in the shop's zone.
    let timeZone: String
    let employeeId: Int
    let role: String
    let writesEnabled: Bool
}

/// Body of the 202/200 responses from register, confirm, resend and password reset.
struct MessageResponse: Decodable, Equatable, Sendable {
    let message: String
}

/// For endpoints that answer 204 No Content.
struct NoContent: Decodable, Equatable, Sendable {}

// MARK: - Request bodies

struct CredentialsBody: Encodable, Sendable {
    let email: String
    let password: String
    var shopId: String?
}

struct EmailBody: Encodable, Sendable {
    let email: String
}

struct ConfirmEmailBody: Encodable, Sendable {
    let userId: String
    let code: String
}

struct ResetPasswordBody: Encodable, Sendable {
    let email: String
    let code: String
    let newPassword: String
}

struct GoogleBody: Encodable, Sendable {
    let idToken: String
    var shopId: String?
}

struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
    var shopId: String?
}
