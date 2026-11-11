import Foundation
import Observation

/// The signed-in state the screens react to.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case starting
        case signedOut
        /// Tokens exist but the API couldn't be reached; keep them and offer a retry.
        case unavailable(String)
        case signedIn(Me)
    }

    private(set) var state: State = .starting
    let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// Restores a saved session on launch.
    func start() async {
        guard client.hasSession else {
            state = .signedOut
            return
        }
        await loadMe()
    }

    func signIn(email: String, password: String) async throws {
        try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        await loadMe()
    }

    /// Always answers with the same message, whether or not the email already has an account.
    func register(email: String, password: String) async throws -> String {
        try await client.send(API.register(email: email.trimmingCharacters(in: .whitespaces), password: password)).message
    }

    func resendConfirmation(email: String) async throws -> String {
        try await client.send(API.resendConfirmation(email: email.trimmingCharacters(in: .whitespaces))).message
    }

    func forgotPassword(email: String) async throws -> String {
        try await client.send(API.forgotPassword(email: email.trimmingCharacters(in: .whitespaces))).message
    }

    func signOut() async {
        await client.signOut()
        state = .signedOut
    }

    /// Screens call this with any error from a signed-in request.
    func handle(_ error: Error) {
        if case APIError.signedOut = error { state = .signedOut }
    }

    private func loadMe() async {
        do {
            state = .signedIn(try await client.send(API.me()))
        } catch APIError.signedOut {
            state = .signedOut
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }
}
