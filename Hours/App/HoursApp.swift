import SwiftUI

@main
struct HoursApp: App {
    @State private var session = SessionStore(client: HoursApp.makeClient())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Theme.brass)
                .onOpenURL { _ = GoogleAuth.handle($0) }
        }
    }

    private static func makeClient() -> APIClient {
        #if DEBUG
        if DemoServer.isEnabled { return DemoServer.makeClient() }
        #endif
        // Each environment keeps its own session: staging and production tokens aren't interchangeable.
        var tokens = KeychainTokenStore()
        if AppConfig.environment != .production { tokens.service += ".\(AppConfig.environment.rawValue)" }
        return APIClient(baseURL: AppConfig.apiBaseURL, tokens: tokens)
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .starting:
                Splash()
            case .signedOut:
                SignInView()
            case let .unavailable(message):
                Unavailable(message: message)
            case let .signedIn(me):
                DayView(me: me)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .safeAreaInset(edge: .top, spacing: 0) {
            if AppConfig.environment == .staging { StagingBanner() }
        }
        .task {
            // Unit tests run inside the app; don't let it call the real API.
            guard !AppConfig.isRunningTests else { return }
            await session.start()
        }
    }
}

/// Marks staging builds on every screen so they're never mistaken for the real book.
private struct StagingBanner: View {
    var body: some View {
        Text("Staging · Booker sandbox".uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Theme.oxblood)
            .accessibilityLabel("Staging build, using the Booker sandbox")
    }
}

private struct Splash: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Hours").font(Theme.display(52)).foregroundStyle(Theme.ink)
            OrnamentRule(width: 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}

private struct Unavailable: View {
    let message: String
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.brass)
            Text("Can't reach the shop.")
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Try again") { Task { await session.start() } }
                .buttonStyle(PrimaryButtonStyle())
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                .foregroundStyle(Theme.oxblood)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
    }
}
