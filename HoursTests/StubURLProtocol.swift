import Foundation
@testable import Hours

/// Answers requests from a per-host handler, so tests running in parallel each get their own fake server.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    /// Returns a client wired to a fresh fake host and a session that routes to `handler`.
    static func makeClient(tokens: any TokenStore, handler: @escaping Handler) -> APIClient {
        let host = "test-\(UUID().uuidString.lowercased()).example"
        lock.withLock { handlers[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return APIClient(baseURL: URL(string: "https://\(host)")!, tokens: tokens, session: URLSession(configuration: configuration))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handlers[request.url?.host() ?? ""] }
        do {
            guard let handler else { throw URLError(.cannotFindHost) }
            let (status, body) = try handler(request, Self.body(of: request))
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession moves the body into a stream before protocols see it.
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// A thread-safe counter/recorder for handlers.
final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _paths: [String] = []

    func record(_ request: URLRequest) { lock.withLock { _paths.append(request.url?.path() ?? "") } }
    var paths: [String] { lock.withLock { _paths } }
    func count(_ path: String) -> Int { paths.filter { $0 == path }.count }
}

func json(_ text: String) -> Data { Data(text.utf8) }

func tokensJSON(access: String, refresh: String) -> Data {
    json("""
    {"accessToken":"\(access)","accessTokenExpiresAt":"2026-11-11T03:24:12.4102421+00:00",
     "refreshToken":"\(refresh)","refreshTokenExpiresAt":"2026-12-11T03:09:12.410242+00:00",
     "shopId":"durham","shops":[{"shopId":"durham","shopName":"Durham","employeeId":1487316,"role":"Barber"}]}
    """)
}

func sampleTokens(access: String = "access-1", refresh: String = "refresh-1") -> AuthTokens {
    AuthTokens(accessToken: access, accessTokenExpiresAt: .now.addingTimeInterval(900),
               refreshToken: refresh, refreshTokenExpiresAt: .now.addingTimeInterval(86_400),
               shopId: "durham", shops: [])
}

let meJSON = json("""
{"userId":"u1","email":"barber@example.com","displayName":null,
 "shops":[{"shopId":"durham","shopName":"Durham","employeeId":1487316,"role":"Barber"}],
 "currentShop":{"shopId":"durham","shopName":"Durham","timeZone":"America/New_York","employeeId":1487316,"role":"Barber","writesEnabled":false}}
""")
