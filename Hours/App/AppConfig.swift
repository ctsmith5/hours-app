import Foundation

enum AppConfig {
    enum Environment: String {
        case production, staging
    }

    /// Set per build configuration in Config/Production.xcconfig and Config/Staging.xcconfig.
    static let environment: Environment = {
        (Bundle.main.object(forInfoDictionaryKey: "HoursEnvironment") as? String).flatMap(Environment.init) ?? .production
    }()

    /// The API this build talks to: production for Debug and Release, staging for the Staging
    /// configuration (the "Hours Staging" scheme). The `API_BASE_URL` environment variable in a
    /// scheme's Run settings overrides it when launching from Xcode, e.g. for a local API.
    static let apiBaseURL: URL = {
        if let override = ProcessInfo.processInfo.environment["API_BASE_URL"], let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           let url = URL(string: configured), url.host() != nil {
            return url
        }
        return URL(string: "https://booker-schedule-bridge-git-483738303584.us-east4.run.app")!
    }()

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
