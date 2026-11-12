import GoogleSignIn
import UIKit

/// Gets a Google ID token for `/api/v1/auth/google`. Our API verifies it and issues its own tokens,
/// so the app never keeps Google's.
@MainActor
enum GoogleAuth {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "Google sign-in isn't set up in this build." }
    }

    /// The iOS OAuth client ID from Config/Google.xcconfig, if one is set.
    static var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return id
    }

    static var isConfigured: Bool { clientID != nil }

    /// Shows Google's sign-in sheet. Returns nil if the user cancels.
    static func idToken() async throws -> String? {
        guard let clientID else { throw NotConfigured() }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenter = topViewController() else { throw NotConfigured() }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else {
                throw URLError(.userAuthenticationRequired)
            }
            return token
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain
                                       && error.code == GIDSignInError.canceled.rawValue {
            return nil
        }
    }

    /// Forgets Google's own session too, so the next sign-in asks which account to use.
    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
