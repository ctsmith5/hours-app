import Foundation

enum AppConfig {
    /// The deployed API on Cloud Run. Override with the `API_BASE_URL` environment variable
    /// in the scheme (Product → Scheme → Edit Scheme → Run → Arguments), e.g. for a staging service.
    static let apiBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["API_BASE_URL"], let url = URL(string: override) {
            return url
        }
        return URL(string: "https://booker-schedule-bridge-git-483738303584.us-east4.run.app")!
    }()

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
