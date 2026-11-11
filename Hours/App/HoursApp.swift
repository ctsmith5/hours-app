import SwiftUI

@main
struct HoursApp: App {
    @State private var session = SessionStore(
        client: APIClient(baseURL: AppConfig.apiBaseURL, tokens: KeychainTokenStore())
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .starting:
                ProgressView()
            case .signedOut:
                SignInView()
            case let .unavailable(message):
                ContentUnavailableView {
                    Label("Can't connect", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await session.start() } }
                    Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                }
            case let .signedIn(me):
                DayView(me: me)
            }
        }
        .task {
            // Unit tests run inside the app; don't let it call the real API.
            guard !AppConfig.isRunningTests else { return }
            await session.start()
        }
    }
}
