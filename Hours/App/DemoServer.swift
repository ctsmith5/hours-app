#if DEBUG
import Foundation

/// A fake API for trying the app without an account: launch with `HOURS_DEMO=1` in the
/// scheme's environment. Debug builds only; it never ships.
final class DemoServer: URLProtocol, @unchecked Sendable {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["HOURS_DEMO"] == "1" }

    static func makeClient() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoServer.self]
        // Starts signed in, so the day view opens straight away.
        let tokens = AuthTokens(accessToken: "demo", accessTokenExpiresAt: .distantFuture, refreshToken: "demo",
                                refreshTokenExpiresAt: .distantFuture, shopId: "durham", shops: [])
        return APIClient(baseURL: URL(string: "https://demo.hours.invalid")!, tokens: InMemoryTokenStore(tokens),
                         session: URLSession(configuration: configuration))
    }

    private static let timeZone = TimeZone(identifier: "America/New_York")!

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let (status, body) = Self.respond(path: url.path(), query: url.query() ?? "")
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        // A short delay so loading states are visible.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) { [self] in
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private static func respond(path: String, query: String) -> (Int, String) {
        switch path {
        case "/api/v1/auth/login", "/api/v1/auth/google", "/api/v1/auth/refresh":
            return (200, """
            {"accessToken":"demo","accessTokenExpiresAt":"2099-01-01T00:00:00Z","refreshToken":"demo",
             "refreshTokenExpiresAt":"2099-01-01T00:00:00Z","shopId":"durham",
             "shops":[{"shopId":"durham","shopName":"Durham","employeeId":1,"role":"Barber"}]}
            """)
        case "/api/v1/auth/logout":
            return (204, "")
        case let p where p.hasPrefix("/api/v1/auth/"):
            return (202, #"{"message":"If that address can be used, we've sent it an email. Check your inbox."}"#)
        case "/api/v1/me":
            return (200, """
            {"userId":"demo","email":"barber@example.com","displayName":"Demo Barber",
             "shops":[{"shopId":"durham","shopName":"Durham","employeeId":1,"role":"Barber"}],
             "currentShop":{"shopId":"durham","shopName":"Durham Barber Co.","timeZone":"America/New_York",
                            "employeeId":1,"role":"Barber","writesEnabled":false}}
            """)
        case "/api/v1/appointments":
            return (200, list(appointments(on: day(from: query))))
        case "/api/v1/breaks":
            return (200, list(breaks(on: day(from: query))))
        default:
            return (404, #"{"title":"Not Found"}"#)
        }
    }

    private static func day(from query: String) -> DateComponents {
        let value = query.split(separator: "=").last.map(String.init) ?? ""
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return DateComponents() }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func appointments(on day: DateComponents) -> [String] {
        // Sundays are closed; other days get a varied book so the timeline has something to show.
        guard let weekday = date(day, 12, 0).map({ calendar.component(.weekday, from: $0) }), weekday != 1 else { return [] }
        let book: [(Int, Int, Int, String, String, [String], String)] = [
            (9, 0, 45, "Marcus", "Bell", ["Skin fade"], "Confirmed"),
            (10, 0, 30, "Luis", "Ortega", ["Line-up"], "Booked"),
            (10, 15, 45, "Jamal", "Carter", ["Kids cut"], "Booked"),
            (11, 15, 60, "Andre", "Thompson", ["Haircut", "Beard trim"], "Confirmed"),
            (13, 30, 45, "Devon", "Reyes", ["Hot towel shave"], "Booked"),
            (14, 30, 30, "Theo", "Nash", ["Taper"], "Booked"),
            (16, 0, 75, "Grant", "Wallace", ["Haircut", "Color"], "Confirmed"),
        ]
        let skip = (day.day ?? 0) % 3 // vary the book a little from day to day
        return book.enumerated().filter { $0.offset % 4 != skip }.compactMap { index, entry in
            let (hour, minute, length, first, last, services, status) = entry
            guard let start = date(day, hour, minute) else { return nil }
            let treatments = services.map { #"{"TreatmentName":"\#($0)"}"# }.joined(separator: ",")
            return """
            {"ID":\(9000 + index),"StartDateTime":"\(wcf(start))","EndDateTime":"\(wcf(start.addingTimeInterval(Double(length) * 60)))",
             "Customer":{"FirstName":"\(first)","LastName":"\(last)"},
             "AppointmentTreatments":[\(treatments)],"Status":{"Name":"\(status)"}}
            """
        }
    }

    private static func breaks(on day: DateComponents) -> [String] {
        guard let start = date(day, 12, 30) else { return [] }
        return [#"{"ID":501,"StartDateTime":"\#(wcf(start))","EndDateTime":"\#(wcf(start.addingTimeInterval(45 * 60)))","Notes":"Lunch"}"#]
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func date(_ day: DateComponents, _ hour: Int, _ minute: Int) -> Date? {
        var parts = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts)
    }

    private static func wcf(_ date: Date) -> String {
        "/Date(\(Int64(date.timeIntervalSince1970 * 1000))-0500)/"
    }

    private static func list(_ items: [String]) -> String {
        #"{"IsSuccess":true,"Results":[\#(items.joined(separator: ","))],"TotalResultsCount":\#(items.count)}"#
    }
}
#endif
