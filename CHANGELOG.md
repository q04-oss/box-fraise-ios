# Changelog

All notable changes to Box Fraise iOS are recorded here.

## Unreleased (session 6 — security & architecture to 10/10)

### Security — critical

- **`PrivacyInfo.xcprivacy` created** — declares UserDefaults, file timestamp, and system boot time API usage; required for App Store submission
- **HMAC signing key moved from binary to Keychain** — generated randomly per-device on first launch; never appears in binary data segment or strings output; server learns the key during App Attest registration
- **`registerAttestation` sends device HMAC key** — server can now validate per-device HMAC signatures independently of App Attest assertions, enabling dual-layer validation
- **Certificate pinning comment with expiry slot** — second hash slot added with instructions; prevents rotation outage
- **`FraiseToken` newtype** — `struct FraiseToken: RawRepresentable, Codable, Hashable, Sendable` replaces the `typealias`; compiler now rejects raw `String` where a session token is expected; `CustomStringConvertible` redacts value from logs; adopted across all Keychain, APIClient, AppAttest, and AppState call sites
- **`FraiseMessaging` converted to actor** — serialises all encrypt/decrypt/publish operations; eliminates data race on ratchet session state
- **One-time prekeys implemented** — `MessagingKeyStore.generateAndStoreOneTimePreKeys` generates OPKs, stores private halves in Keychain; `consumeOneTimePreKey` deletes after single use (consume-once semantics); `uploadOneTimePreKeys` uploads to key server; decrypt path consumes OPKs on X3DH receive; enables full 4-DH X3DH
- **Signed prekey rotation** — rotates weekly; timestamp tracked in UserDefaults; checked on every `publishPublicKeys` call; a compromised signed prekey has at most a 7-day validity window for new session establishment
- **Key publication retry with exponential backoff** — 4 attempts at 1s/2s/4s delays; handles 429 rate-limiting with `Retry-After` header; throws `FraiseMessagingError.publishFailed` after exhausting retries
- **Fresh jailbreak check on sign-in** — `AppSecurity.isJailbrokenFresh()` bypasses the memoised cache; prevents hook-then-cache attacks where an attacker intercepts the first check and returns false permanently
- **429 rate-limit handling** — `APIError.rateLimited(retryAfter: TimeInterval)` extracted from HTTP 429 responses with `Retry-After` header parsing

### Architecture

- **`SWIFT_STRICT_CONCURRENCY = complete`** — enabled in both Debug and Release build configurations; compiler now enforces actor isolation correctness
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`** — enabled in Release builds
- **`MessagingKeyStore` OPK support** — `rotateSignedPreKey()`, `generateAndStoreOneTimePreKeys(count:)`, `consumeOneTimePreKey(id:)`, `keychainDeleteKey` added; private keys stored in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- **`PlatformMessage.oneTimePreKeyId`** — new optional field enables OPK consumption on decrypt
- **`APIClient.deviceSigningKeyData`** — exposes HMAC key bytes for attestation registration

### Observability

- `Logger` added to `AppSecurity`, `AppAttest`, `FraiseMessaging` with `os.log` structured logging
- Security enforcement decisions (jailbreak result, debugger detection, simulator rejection) logged at appropriate levels (info/warning/critical)
- Attestation success/failure and key ID prefix logged
- Key publication attempts and outcomes logged with retry count (session 5 — methodically considered)

### Naming precision
- `AppState.refresh()` → `refreshMapData()` — scope is map data only, not full user refresh
- `AppState.handle(_:)` → `routeAPIError(_:)` — name reflects the single responsibility
- `AppState.writeWidgetData()` → `updateHomeScreenWidget()` — destination is explicit
- `MeetPanel.startMeet()` → `beginMeetSession()` — communicates BLE + token init
- `MeetPanel.confirm(theirToken:)` → `recordMeeting(theirToken:)` — name matches the network call
- `ProfilePanel.reloadProfile()` → `fetchProfile()` — consistent with `fetch` prefix on APIClient

### Architecture
- `AppState.invalidateBusinessCaches()` — single call site for all three caches; `businesses.didSet` and `userLocation.didSet` both use it, fixing the gap where `_nearestCollectionCache` wasn't invalidated on business change
- `AppState.signIn(response:)` race guard — `guard user == nil` prevents double key publication from rapid taps
- `AppState.refreshUser()` routes 401 through `routeAPIError(_:)` — session expiry during background refresh now triggers re-auth
- `AppState.bootstrap()` phase comments — 4 explicit phases document the intentional load order
- `MeetPanel.myToken` removed — `session.myToken` is the single source of truth
- `Config.validate()` — asserts at launch in debug if Stripe key is placeholder value
- `FraiseMessaging` private init — singleton enforced, consistent with AppAttest and APIClient
- `FraiseMessaging` top-of-file Signal protocol overview comment
- `AppAttest` top-of-file expanded comment — X3DH flow, assertion mechanics, fallback documented

### Theme
- `Radius.sheet = 24`, `Radius.callout = 20` — all hardcoded radii replaced with tokens
- `Animation.fraiseSpring`, `.fraiseCallout`, `.fraiseSkeleton` — named animation constants
- `AnyTransition.fraisePanelTransition` — panel transition extracted from SheetContent inline
- `PanelHeader` shared component — eliminates repeated `HStack { FraiseBackButton; Spacer; Text; Spacer; action }` across all panels
- `SkeletonStyle` enum (`.narrow`, `.wide`) replaces `Bool` parameter on `FraiseSkeletonRow`
- `FraiseDateFormatter.date(from:)` — fast-path / fallback comments and doc comment on nil contract
- `FraiseColors.light` palette comment explaining warm-gray design decisions

### Correctness
- `AkeneInvitation.isExpired` fail-closed — unparseable `expiresAt` now returns `true` instead of `false`
- `Business.displayCity` returns `String?` — callers that displayed empty strings now handle absence explicitly
- `NFCVerifyPanel.addedBusinessCode: String?` → `businessContactAdded: Bool` — single Bool, no string comparison
- `NFCScanDelegate` multi-tag guard — `tags.count == 1` check with descriptive invalidation message
- `UserKeyBundle` debug description — key material redacted from all log output
- `JoinResponse` debug description — Stripe client secret redacted
- `FraiseContact.resolvedContactId` — eliminates three-site `contactId ?? id` pattern
- `ComposeSheet` uses `contact.resolvedContactId` throughout
- `NFCProvenance` shared struct — provenance fields unified between `NFCVerifyResult` and `NFCReorderResult`
- `PastOrderStatus` enum — status comparisons use typed enum instead of raw strings
- `MessageType` enum — thread row preview logic uses typed enum instead of raw strings
- `AppDelegate.appState` marked `weak` — retain cycle prevented, nil case logged with `os_log`
- `AppDelegate` calls `Config.validate()` first in `didFinishLaunching`
- `ThreadView` poll loop capped at 200 iterations — prevents indefinite battery drain
- `HomePanel.debounceTask?.cancel()` in `.onDisappear` — prevents stale state write after navigation

### API client
- `request()` explicit `timeoutInterval = 30` — faster error surfacing than the 60s URLRequest default
- `rawRequest()` explicit `timeoutInterval = 15` — staff/walk-in on local network should respond faster
- Direct URL string construction in `request()` — `appendingPathComponent` leading-slash ambiguity eliminated
- `broadcastMessage` contract comment — caller must encrypt before calling

### Comments
- `Keychain.withToken` threading contract documented
- `AppState.joinedPopupIds` session-only explanation
- `AppState.openToDates`/`prevAkeneRank` observation contract documented
- `AppState.nearestCollection` fallback behaviour explained
- `PopupsPanel.prepareJoin` defer comment — why joining isn't cleared when paymentSheet is set
- `MeetSession.start()` identifier stability note
- `HomePanel.season` hemisphere caveat
- `MessageCache.minKey` sentinel value documented
- `Security.enforce()` doc comment — call site contract and debug-build behaviour

### ContentView
- `SheetContent` uses `Animation.fraiseSpring` and `AnyTransition.fraisePanelTransition`
- `BusinessCallout` uses `Radius.callout`

### UI consistency
- `ComposeSheet` and `StatusEditorSheet` get `.scrollDismissesKeyboard(.interactively)`
- `OfflineBanner` and `ReauthBanner` get `#Preview` blocks

### Documentation
- `README.md` created — architecture, security model, Signal flow, setup instructions

### Correctness fixes
- `pendingScreen: String?` added to `AppState` — was referenced by `ContentView` and `AppDelegate` but absent from the model (compile error)
- `BoxUser` initialiser in `NFCVerifyPanel.verify()` now preserves all 8 fields — previous call omitted 5 required parameters
- `FraisePopup` conforms to `PricedItem` — `popup.priceFormatted` was used in `PopupsPanel` without the conformance
- `HomePanel.approvedPartnerCount` uses `.partner` enum case instead of raw string `"partner"`
- Three broken `private func FraiseDateFormatter.*` definitions removed from `MessagesPanel` — dotted function names are invalid Swift
- `MeetPanel.stateIconColor` exhaustively covers all `MeetState` cases — `default:` removed
- `MeetSession.isTerminal` exhaustively covers all `MeetState` cases — `default:` removed
- `MeetPanel.loading` state removed — declared but never used
- `navigate(to:)` now used everywhere panel changes — all stray `panel = .xxx` assignments eliminated (AppState, BoxFraiseApp, all panels)
- `AppState.nearestCollection` force-unwraps `a.lat!` replaced with `guard let` — safe even though coordinate-nil businesses are pre-filtered

### Architecture
- `APIClient.swift` split into domain extension files: `+Auth`, `+Orders`, `+Messaging`, `+Connections`, `+Akene`, `+Dates`, `+Businesses`
- `ViewState<T>` adopted in `OrderHistoryPanel`, `ReferralsPanel`, `StandingOrdersPanel`, `MessagesPanel`
- `FraiseErrorView` used in `OrderHistoryPanel` and `StandingOrdersPanel` error states
- `AppState.route(to:)` refactored to compute `destination: Panel` then call `navigate(to:)` — single write path
- `BusinessType`, `FraiseObjectType`, `ReplyContext`, `FraiseColors` marked `Sendable`
- `defer { loadState = .loaded(()) }` pattern in `ReferralsPanel.load()`
- All remaining `Color(hex:)` calls in `PopupsPanel`, `OrderHistoryPanel`, `NFCVerifyPanel` replaced with semantic constants
- `Radius.card` used in `PopupsPanel` — hardcoded 16 replaced

### Comments
- `MessageCache.maxSize` documents the 2000-entry / ~400 KB in-process budget reasoning
- `Keychain.saveMetadata` documents why `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is used for App Attest IDs

### Security
- Certificate pinning with SPKI hash verification (SHA-256, RFC 5480/3279 DER headers)
- App Attest integration — key ID and attestation state stored in Keychain, not UserDefaults
- Jailbreak detection: file paths, sandbox write, URL schemes, DYLD injection, dylib scan, Frida port
- `PT_DENY_ATTACH` via ptrace in release builds; sysctl P_TRACED check
- `OSAllocatedUnfairLock` on jailbreak result cache
- Simulator rejection in release builds (`exit(0)`)
- Screen recording detection via `UIScreen.capturedDidChangeNotification` — privacy overlay fires immediately
- Background snapshot protection via `scenePhase == .background` overlay

### Architecture
- `ViewState<T>` enum (`idle / loading / loaded / failed`) — shared lifecycle for data-fetching views
- `FraisePrimaryButtonStyle`, `FraiseSecondaryButtonStyle` — `ButtonStyle` conformances
- `FraiseCardModifier` / `.fraiseCard()` — shared card appearance
- `FraiseErrorView` — shared error + retry component
- `StatusDot` — shared online-presence indicator
- `FraiseDateFormatter` — single pair of cached `ISO8601DateFormatter` instances; 7 named format methods
- `AppKeys.swift` — all `@AppStorage`, `UserDefaults`, `Keychain`, and notification payload key strings as typed constants
- `Config.swift` — reads Stripe key from `Info.plist` with test-key fallback; documents xcconfig path
- `FraiseToken` typealias — explicit type for session tokens
- `DeepLinkPath` enum — routing strings are compile-time constants
- `AppState.navigate(to:)` — all panel navigation routed through a single method; `panel` is `private(set)`
- `AppState.route(to:)` — deep-link routing centralised, uses `DeepLinkPath.rawValue`
- `nearestCollection`, `approvedBusinesses`, `unapprovedBusinesses` — cached and invalidated via `didSet`
- `openToDates`, `prevAkeneRank` moved from view `@AppStorage` to `AppState`
- `DiscoveredPeer` named struct replaces `(CBPeripheral, Int)` tuple in `MeetSession`
- `ReplyContext` struct replaces dual `replyToId?/replyToSnippet?` optionals on `PlatformMessage`
- `BusinessType`, `FraiseObjectType` enums replace raw `String` comparisons
- `BoxUser.verified`, `isShop` — non-optional `Bool` with Decodable defaulting to `false`
- `BoxUser.initial` — replaces 4-site `.prefix(1).uppercased()` chain
- `MessageCache` eviction — O(1) via `minKey` tracking; was O(n log n) sort
- `MessageThread.hasUnread`, `AkeneInvitation.isExpired`, `AkeneInvitation.isCompleted`, `DateInvitation.isDeclined/isOpened`, `PastOrder.isReady`, `FraisePopup.isCancelled/isClosed`, `StandingOrder.isPaused/isCancelled`, `AkeneMyEvent.isCompleted`, `MeetState.isTerminal`, `Panel.CustomStringConvertible`
- `FraiseInboxPanel.swift` deleted — not routed to since `MessagesPanel` was introduced

### UI/UX
- `Radius` enum (`card` 14, `button` 12, `field` 10, `chip` 8)
- `Divide` enum (`row` 0.4, `section` 0.6)
- Semantic color constants (`Color.fraiseGreen/Red/Orange/Blue`) — all `Color(hex:)` calls replaced
- `.contextMenu` on message bubbles replaces `.onLongPressGesture`
- `.scrollDismissesKeyboard(.interactively)` in `ThreadView`
- `ThreadView` compose bar moved to `.safeAreaInset(edge: .bottom)` — correct keyboard avoidance
- `.presentationDragIndicator(.visible)` on all sheets
- `.interactiveDismissDisabled()` on `MemoryPromptSheet`
- `.contentShape(Rectangle())` on all icon-only buttons
- `.refreshable` on `ProfilePanel`, `AkenePanel` leaderboard
- `.contentTransition(.numericText())` on akène count and rank position
- `FraiseSkeletonRow` respects `accessibilityReduceMotion`; hidden from VoiceOver
- `HomePanel` search debounced 300 ms
- `ThreadView` polling backed off to 15 s after 5 quiet rounds
- `Haptics` — `UIFeedbackGenerator.prepare()` called before anticipated moments
- `accessibilityLabel` on back, compose, send, attach, clear-reply buttons

### Concurrency
- `MeetSession` BT delegates routed to main queue (`queue: nil`) — eliminated data race on `discovered` dict
- `Frida` port check backgrounded in `enforce()` — eliminates 300 ms main-thread stall at launch
- `Keychain.withToken` — non-throwing and throwing variants; eliminates `guard let token` boilerplate

### Tests
- `FraiseDateFormatterTests` — 8 cases covering all 7 format methods and edge cases
- `BoxUserInitialTests` — nil, empty, single-char, lowercase
- `AkeneInvitationStateTests` — all status/eventStatus combinations, expiry
- `MessageCacheTests` — set, get, overwrite
- `ViewStateTests` — all 4 states
- `SecurityTests` — simulator jailbreak false-negative, debug check
- `DeepLinkPathTests` — raw value completeness
- `PastOrderTests` — full lifecycle
