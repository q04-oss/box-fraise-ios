# Box Fraise iOS

Native iOS app for the box fraise platform — strawberry collection orders, social identity, BLE proximity meeting, and end-to-end encrypted messaging.

---

## Architecture

### Navigation model

All panel navigation flows through a single write path:

```
AppState.navigate(to: Panel)
    ↓
AppState.panel: Panel   (private(set))
    ↓
SheetContent             (reads state.panel, renders the active panel)
```

`panel` is `private(set)`. Nothing outside `AppState` writes to it directly. Deep-link routing goes through `AppState.route(to: screenName)`, which resolves the string to a typed `Panel` case and calls `navigate(to:)`.

### State ownership

`AppState` is `@MainActor @Observable`. It is created as `@State` in `BoxFraiseApp` — scene-scoped by design. All mutation happens on the main actor.

```
BoxFraiseApp (@State)
    └── AppState (@MainActor @Observable)
            ├── panel: Panel            (navigation)
            ├── user: BoxUser?          (auth)
            ├── businesses: [Business]  (map data — cached)
            ├── popups: [FraisePopup]   (map data)
            └── orderHistory: [PastOrder]
```

Derived caches (`approvedBusinesses`, `unapprovedBusinesses`, `nearestCollection`) are invalidated together via `invalidateBusinessCaches()`, called from `businesses.didSet` and `userLocation.didSet`.

### Data flow

```
APIClient (actor)
    → AppState (MainActor)
        → SwiftUI views (read-only via @Environment)
```

`APIClient` is an `actor`. All network calls are `async throws`. Panels call `Keychain.withToken { token in ... }` instead of the `guard let token` pattern. 401 responses bubble up through `AppState.routeAPIError(_:)` → `handleUnauthorized()`.

### ViewState lifecycle

Async data-loading views use `ViewState<T>` instead of `loading: Bool`:

```swift
enum ViewState<T> { case idle, loading, loaded(T), failed(String) }
```

`FraiseErrorView` renders the `.failed` state with a retry closure. `FraiseSkeletonRow(style:)` renders the `.loading` state.

---

## Security model

Four layers, all active simultaneously in release builds:

| Layer | Implementation |
|-------|---------------|
| **Certificate pinning** | SPKI SHA-256 hash verification in `PinningDelegate`. Always keep two hashes: current + next. |
| **HMAC request signing** | `HMAC<SHA256>` over `method + path + timestamp + body` on every request in `APIClient.request()`. |
| **App Attest assertions** | `DCAppAttestService` generates a Secure Enclave key pair; Apple signs the public key. Each request carries an ECDSA assertion over the request hash. Falls back to HMAC-only on unsupported devices. |
| **Runtime integrity** | Jailbreak detection (7 vectors), PT_DENY_ATTACH, sysctl P_TRACED check, Frida port check (backgrounded), simulator rejection in release. |

Additional: screen recording detection, background snapshot overlay, biometric-gated Keychain for session tokens.

### Certificate rotation

```bash
# Get current cert SPKI hash
openssl s_client -connect fraise.box:443 </dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | base64
```

Add the new hash to `PinningDelegate.pinnedHashes` **before** the cert rotates. Remove the old hash only after all clients have updated. A single-hash gap causes a global outage.

---

## End-to-end messaging (Signal Protocol)

```
First message to a new contact:
    X3DH key exchange
        → identity key + signed prekey + (optional) one-time prekey
        → establishes shared secret
        → initialises Double Ratchet state

Subsequent messages:
    Double Ratchet
        → per-message key derivation
        → forward secrecy: old keys deleted after use
        → break-in recovery: fresh keys on next send
```

All key material is in-memory or Keychain only — never UserDefaults, iCloud, or logs. `UserKeyBundle` and Signal session state have custom `debugDescription` implementations that redact key material.

---

## Setup

### 1. Secrets

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
# edit Secrets.xcconfig and set:
#   STRIPE_PUBLISHABLE_KEY = pk_live_...
```

Add `Secrets.xcconfig` to your Debug and Release configurations in Xcode:
`Project → Info → Configurations → ▸ Add Config File`

Add to `Info.plist`:
```xml
<key>STRIPE_PUBLISHABLE_KEY</key>
<string>$(STRIPE_PUBLISHABLE_KEY)</string>
```

`Config.validate()` is called at launch and asserts in debug if the key is still the placeholder value.

### 2. Build settings (recommended)

In the Xcode project, under `Build Settings`:
- `SWIFT_STRICT_CONCURRENCY = complete` — surfaces actor-isolation violations at compile time
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` (Release only) — warnings in release are future bugs

### 3. Run tests

```bash
xcodebuild test \
  -scheme BoxFraise \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Test classes: `FraiseDateFormatterTests`, `BoxUserInitialTests`, `AkeneInvitationStateTests`, `MessageCacheTests`, `ViewStateTests`, `SecurityTests`, `DeepLinkPathTests`, `PastOrderTests`.

---

## Key files

| File | Responsibility |
|------|---------------|
| `AppState.swift` | Single source of truth for all app state and navigation |
| `AppKeys.swift` | All string constants (storage keys, deep-link paths) |
| `Config.swift` | Build-time configuration, `FraiseToken` typealias |
| `APIClient.swift` | Network core (pinned session, HMAC signing, App Attest) |
| `APIClient+*.swift` | Domain-grouped endpoint extensions |
| `Models.swift` | All Codable model types |
| `Theme.swift` | Colors, typography, spacing, animation vocabulary, shared components |
| `Security.swift` | Runtime integrity enforcement |
| `Keychain.swift` | Secure credential storage, `withToken` helper |
| `AppAttest.swift` | Apple App Attest integration |
| `FraiseMessaging.swift` | Signal Protocol encrypt/decrypt coordinator |
| `MeetSession.swift` | CoreBluetooth BLE proximity session |
| `ContentView.swift` | Map view, sheet router, location manager |
