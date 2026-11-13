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

## Design

Classic barbershop: cream paper and charcoal ink, brass accents, a barber-pole
stripe, and New York (the system serif) for headings. Colors are in
`Assets.xcassets` with dark-mode variants; shared styles are in
`Hours/App/Theme.swift`. The day view is an hour-by-hour timeline
(`TimelineLayout` places overlapping bookings side by side).

**Demo mode** (Debug builds only): enable `HOURS_DEMO` in the scheme's Run
environment variables to use a fake API with a sample book. It starts signed in.

## Google sign-in

1. Google Cloud Console (project CONTROL) → APIs & Services → Credentials →
   Create credentials → OAuth client ID → **iOS**, bundle ID `com.ctsmith5.hours`.
2. Put the client ID and its reversed form ("iOS URL scheme" on the same page) in
   `Config/Google.xcconfig`. They ship in the app, so they aren't secrets.
3. Add the same client ID to `GOOGLE_CLIENT_IDS` in the API's
   `deploy/cloudrun.env` (comma-separated with the web client ID), then run
   `deploy/cloudrun.sh deploy`, so the API accepts tokens issued to the app.

The Google button only appears once step 2 is done.

## TestFlight

One-time setup:

1. Xcode → Settings → Accounts: sign in with the Apple ID on team `2779EQ3QB6`.
2. [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+** → New App: platform iOS,
   bundle ID `com.ctsmith5.hours` (if it isn't listed, register it under Certificates, Identifiers & Profiles → Identifiers),
   SKU `hours-ios`. The name must be unique on the App Store.

Each release (commit first; the build number is the commit count):

```bash
scripts/testflight.sh
```

Then in App Store Connect → TestFlight, add testers. People on your App Store Connect team can
test as soon as the build finishes processing. Anyone else goes in an external group, which needs a
one-time Beta App Review and the test information (feedback email, sign-in details for the reviewer).

## API URL

The app uses the deployed Cloud Run URL in `Hours/App/AppConfig.swift`. To point
it somewhere else, set `API_BASE_URL` in the scheme's Run environment variables.

## Tests

```bash
xcodebuild test -project Hours.xcodeproj -scheme Hours -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Not done yet

- Opening email confirmation and reset links in the app (universal links); for now they open the web app.
- Typed Booker models once real responses are checked.
- Signing team and App Store setup.
