import Foundation
import Testing
@testable import Hours

@Suite struct APIClientTests {
    @Test func signInSendsCredentialsAndKeepsTokens() async throws {
        let store = InMemoryTokenStore()
        let client = StubURLProtocol.makeClient(tokens: store) { request, body in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path() == "/api/v1/auth/login")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
            #expect(sent == ["email": "barber@example.com", "password": "correct horse battery"])
            return (200, tokensJSON(access: "access-1", refresh: "refresh-1"))
        }

        let tokens = try await client.signIn(email: "barber@example.com", password: "correct horse battery")

        #expect(tokens.accessToken == "access-1")
        #expect(tokens.shops.first?.employeeId == 1487316)
        #expect(store.load() == tokens)
    }

    @Test func signedInCallsSendTheBearerToken() async throws {
        let client = StubURLProtocol.makeClient(tokens: InMemoryTokenStore(sampleTokens())) { request, _ in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
            return (200, meJSON)
        }

        let me = try await client.send(API.me())

        #expect(me.currentShop?.timeZone == "America/New_York")
        #expect(me.currentShop?.writesEnabled == false)
    }

    @Test func withoutASessionSignedInCallsFailWithoutTouchingTheNetwork() async {
        let recorder = Recorder()
        let client = StubURLProtocol.makeClient(tokens: InMemoryTokenStore()) { request, _ in
            recorder.record(request)
            return (200, meJSON)
        }

        await #expect(throws: APIError.signedOut) { try await client.send(API.me()) }
        #expect(recorder.paths.isEmpty)
    }

    @Test func expiredAccessTokenIsRefreshedOnceAndTheCallRetried() async throws {
        let store = InMemoryTokenStore(sampleTokens())
        let recorder = Recorder()
        let client = StubURLProtocol.makeClient(tokens: store) { request, body in
            recorder.record(request)
            switch request.url?.path() {
            case "/api/v1/auth/refresh":
                let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
                #expect(sent?["refreshToken"] == "refresh-1")
                return (200, tokensJSON(access: "access-2", refresh: "refresh-2"))
            default:
                let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                return authorized ? (200, meJSON) : (401, json(#"{"title":"Unauthorized"}"#))
            }
        }

        let me = try await client.send(API.me())

        #expect(me.email == "barber@example.com")
        #expect(recorder.paths == ["/api/v1/me", "/api/v1/auth/refresh", "/api/v1/me"])
        #expect(store.load()?.refreshToken == "refresh-2")
    }

    @Test func concurrentUnauthorizedCallsShareOneRefresh() async throws {
        let store = InMemoryTokenStore(sampleTokens())
        let recorder = Recorder()
        let client = StubURLProtocol.makeClient(tokens: store) { request, _ in
            recorder.record(request)
            if request.url?.path() == "/api/v1/auth/refresh" {
                Thread.sleep(forTimeInterval: 0.05) // Let the other calls hit their 401s first.
                return (200, tokensJSON(access: "access-2", refresh: "refresh-2"))
            }
            let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
            return authorized ? (200, meJSON) : (401, Data())
        }

        async let first = client.send(API.me())
        async let second = client.send(API.me())
        async let third = client.send(API.me())
        let results = try await [first, second, third]

        #expect(results.count == 3)
        #expect(recorder.count("/api/v1/auth/refresh") == 1)
    }

    @Test func rejectedRefreshSignsOutAndForgetsTokens() async {
        let store = InMemoryTokenStore(sampleTokens())
        let client = StubURLProtocol.makeClient(tokens: store) { request, _ in
            (401, json(#"{"title":"Session expired."}"#))
        }

        await #expect(throws: APIError.signedOut) { try await client.send(API.me()) }
        #expect(store.load() == nil)
    }

    @Test func networkFailureDuringRefreshKeepsTokens() async {
        let store = InMemoryTokenStore(sampleTokens())
        let client = StubURLProtocol.makeClient(tokens: store) { request, _ in
            if request.url?.path() == "/api/v1/auth/refresh" { throw URLError(.notConnectedToInternet) }
            return (401, Data())
        }

        await #expect { try await client.send(API.me()) } throws: { error in
            if case APIError.transport = error { true } else { false }
        }
        #expect(store.load() != nil)
    }

    @Test func problemDetailsBecomeTypedErrors() async {
        let client = StubURLProtocol.makeClient(tokens: InMemoryTokenStore()) { _, _ in
            (403, json(#"{"title":"Confirm your email before signing in.","status":403,"code":"email_not_confirmed"}"#))
        }

        await #expect { try await client.signIn(email: "a@b.c", password: "x") } throws: { error in
            guard let error = error as? APIError else { return false }
            return error.status == 403 && error.code == "email_not_confirmed"
                && error.localizedDescription == "Confirm your email before signing in."
        }
    }

    @Test func aBare404MeansTheRequestNeverReachedTheAPI() async {
        let client = StubURLProtocol.makeClient(tokens: InMemoryTokenStore()) { _, _ in
            (404, json("<html><body>Error: Page not found</body></html>"))
        }

        await #expect { try await client.signIn(googleIdToken: "token") } throws: { error in
            (error as? APIError)?.localizedDescription.hasPrefix("Couldn't reach the server (404)") == true
        }
    }

    @Test func anAPI404KeepsItsOwnMessage() {
        let error = APIError.http(status: 404, problem: Problem(title: "Appointment not found."))
        #expect(error.localizedDescription == "Appointment not found.")
    }

    @Test func validationErrorsShowTheFirstFieldMessage() {
        let error = APIError.http(status: 400, problem: Problem(title: "One or more validation errors occurred.",
                                                                errors: ["email": ["Enter a valid email address."]]))
        #expect(error.localizedDescription == "Enter a valid email address.")
    }

    @Test func appointmentsAskForTheDayAndDecodeBookerResults() async throws {
        let client = StubURLProtocol.makeClient(tokens: InMemoryTokenStore(sampleTokens())) { request, _ in
            #expect(request.url?.path() == "/api/v1/appointments")
            #expect(request.url?.query() == "date=2026-11-12")
            return (200, json(#"{"IsSuccess":true,"Results":[{"ID":42},{"ID":43}],"TotalResultsCount":2}"#))
        }

        let list = try await client.send(API.appointments(on: "2026-11-12"))

        #expect(list.isSuccess == true)
        #expect(list.results.count == 2)
    }

    @Test func signOutForgetsTokensEvenWhenTheServerIsUnreachable() async {
        let store = InMemoryTokenStore(sampleTokens())
        let client = StubURLProtocol.makeClient(tokens: store) { _, _ in throw URLError(.timedOut) }

        await client.signOut()

        #expect(store.load() == nil)
    }
}
