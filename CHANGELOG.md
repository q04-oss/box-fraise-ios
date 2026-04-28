# Changelog

All notable changes to Box Fraise iOS are recorded here.

## Unreleased

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
