# Hours (iOS)

Native SwiftUI app for barbers, backed by the Schedule Bridge API
(`booker-schedule-bridge`, .NET on Google Cloud Run). Booker stays the system of
record; the app only talks to our API.

Requires Xcode 26 and iOS 17+.

```bash
open Hours.xcodeproj
```

## Layout

| Path | What |
|---|---|
| `Hours/Networking/APIClient.swift` | Actor that sends requests, attaches the access token, and on a 401 refreshes once and retries. Concurrent 401s share one refresh, because refresh tokens rotate and reusing one revokes the session. |
| `Hours/Networking/Endpoint.swift` | `Endpoint<Response>` and `API`, one function per API route under `/api/v1`. |
| `Hours/Networking/Models.swift` | `AuthTokens`, `Me`, `CurrentShop`, request bodies. |
| `Hours/Networking/APIError.swift` | ProblemDetails from the API as `APIError` (status, `code` such as `email_not_confirmed`, field errors). |
| `Hours/Networking/TokenStore.swift` | Keychain storage (this device only, after first unlock), plus an in-memory store for tests. |
| `Hours/Networking/Booker.swift`, `JSONValue.swift` | Booker lists are passed through raw until their schemas are verified. `ScheduleItem` reads the fields it can find and keeps the raw JSON. |
| `Hours/Features` | Session state, sign in / create account, and the day view. |
| `HoursTests` | Swift Testing suites against a stubbed URL protocol. No test touches the real API. |

## API URL

The app uses the deployed Cloud Run URL in `Hours/App/AppConfig.swift`. To point
it somewhere else, set `API_BASE_URL` in the scheme's Run environment variables.

## Tests

```bash
xcodebuild test -project Hours.xcodeproj -scheme Hours -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Not done yet

- Sign in with Google (needs the Google Sign-In SDK and an iOS OAuth client ID added to the API's `Google:ClientIds`).
- Opening email confirmation and reset links in the app (universal links); for now they open the web app.
- Typed Booker models once real responses are checked.
- Signing team and App Store setup.
