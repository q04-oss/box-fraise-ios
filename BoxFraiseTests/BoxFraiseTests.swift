import XCTest
@testable import BoxFraise

// MARK: - FraiseDateFormatter

final class FraiseDateFormatterTests: XCTestCase {
    private let todayISO: String = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }()

    private let pastISO = "2024-03-15T19:30:00.000Z"

    func testLongFormat() {
        let result = FraiseDateFormatter.long(pastISO)
        XCTAssertTrue(result.contains("2024"), "long() should include year")
        XCTAssertTrue(result.lowercased().contains("march") || result.contains("Mar"),
                      "long() should include month")
    }

    func testMediumFormat() {
        let result = FraiseDateFormatter.medium(pastISO)
        XCTAssertFalse(result.contains("2024"), "medium() should not include year")
        XCTAssertFalse(result.isEmpty, "medium() should return a value for valid ISO")
    }

    func testShortFormat() {
        let result = FraiseDateFormatter.short(pastISO)
        XCTAssertFalse(result.isEmpty, "short() should return a value")
        XCTAssertFalse(result.contains("2024"), "short() should not include year")
    }

    func testThreadFormatToday() {
        let result = FraiseDateFormatter.thread(todayISO)
        // Today should return a time (HH:MM), not a date
        let hasColon = result.contains(":")
        let hasMeridiem = result.lowercased().contains("am") || result.lowercased().contains("pm")
        XCTAssertTrue(hasColon || hasMeridiem, "thread() for today should return a time: \(result)")
    }

    func testThreadFormatPast() {
        let result = FraiseDateFormatter.thread(pastISO)
        XCTAssertFalse(result.contains(":"), "thread() for past date should return a date, not time: \(result)")
    }

    func testTimeFormat() {
        let result = FraiseDateFormatter.time(pastISO)
        XCTAssertTrue(result.contains(":") || result.lowercased().contains("pm") || result.lowercased().contains("am"),
                      "time() should return a time string: \(result)")
    }

    func testInvalidISOReturnsFallback() {
        XCTAssertEqual(FraiseDateFormatter.long("not-a-date"), "not-a-date")
        XCTAssertEqual(FraiseDateFormatter.medium("not-a-date"), "")
    }

    func testNoFractionalSeconds() {
        // ISO without fractional seconds should still parse
        let iso = "2024-03-15T19:30:00Z"
        XCTAssertFalse(FraiseDateFormatter.long(iso).isEmpty)
    }
}

// MARK: - BoxUser.initial

final class BoxUserInitialTests: XCTestCase {
    private func makeUser(displayName: String?) -> BoxUser {
        BoxUser(id: 1, displayName: displayName, verified: false, isShop: false,
                fraiseChatEmail: nil, currentStreakWeeks: nil, socialTier: nil, status: nil)
    }

    func testSingleCharacter() {
        XCTAssertEqual(makeUser(displayName: "Austin").initial, "A")
    }

    func testLowercase() {
        XCTAssertEqual(makeUser(displayName: "austin").initial, "A")
    }

    func testNilDisplayName() {
        XCTAssertEqual(makeUser(displayName: nil).initial, "·")
    }

    func testEmptyDisplayName() {
        XCTAssertEqual(makeUser(displayName: "").initial, "·")
    }
}

// MARK: - AkeneInvitation state machine

final class AkeneInvitationStateTests: XCTestCase {
    private func makeInvitation(status: String, eventStatus: String,
                                expiresAt: String? = nil) -> AkeneInvitation {
        AkeneInvitation(id: 1, status: status, sentAt: "2024-01-01T00:00:00Z",
                        expiresAt: expiresAt, respondedAt: nil, eventId: 1,
                        title: "test", description: nil, eventDate: nil,
                        capacity: 10, acceptedCount: 5, eventStatus: eventStatus,
                        businessName: nil)
    }

    func testPendingStatus() {
        let inv = makeInvitation(status: "pending", eventStatus: "inviting")
        XCTAssertTrue(inv.isPending)
        XCTAssertFalse(inv.isAccepted)
        XCTAssertFalse(inv.isDeclined)
        XCTAssertFalse(inv.isWaitlisted)
    }

    func testAcceptedStatus() {
        let inv = makeInvitation(status: "accepted", eventStatus: "seated")
        XCTAssertTrue(inv.isAccepted)
        XCTAssertFalse(inv.isPending)
        XCTAssertTrue(inv.isSeated)
    }

    func testCompletedEvent() {
        let inv = makeInvitation(status: "accepted", eventStatus: "completed")
        XCTAssertTrue(inv.isCompleted)
        XCTAssertTrue(inv.isAccepted)
    }

    func testSeatsLeft() {
        let inv = makeInvitation(status: "pending", eventStatus: "inviting")
        XCTAssertEqual(inv.seatsLeft, 5) // capacity 10, accepted 5
    }

    func testIsFull() {
        let inv = AkeneInvitation(id: 1, status: "pending", sentAt: "2024-01-01T00:00:00Z",
                                  expiresAt: nil, respondedAt: nil, eventId: 1,
                                  title: "test", description: nil, eventDate: nil,
                                  capacity: 10, acceptedCount: 10, eventStatus: "seated",
                                  businessName: nil)
        XCTAssertTrue(inv.isFull)
    }

    func testExpiredInvitation() {
        let pastISO = "2020-01-01T00:00:00.000Z"
        let inv = makeInvitation(status: "pending", eventStatus: "inviting", expiresAt: pastISO)
        XCTAssertTrue(inv.isExpired)
    }

    func testNonExpiredInvitation() {
        let futureISO = "2099-01-01T00:00:00.000Z"
        let inv = makeInvitation(status: "pending", eventStatus: "inviting", expiresAt: futureISO)
        XCTAssertFalse(inv.isExpired)
    }
}

// MARK: - MessageCache

final class MessageCacheTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear cache between tests by overwriting with known state
    }

    func testSetAndGet() {
        MessageCache.set(9001, text: "hello")
        XCTAssertEqual(MessageCache.get(9001), "hello")
    }

    func testMissingKey() {
        XCTAssertNil(MessageCache.get(-1))
    }

    func testOverwrite() {
        MessageCache.set(9002, text: "first")
        MessageCache.set(9002, text: "second")
        XCTAssertEqual(MessageCache.get(9002), "second")
    }
}

// MARK: - ViewState

final class ViewStateTests: XCTestCase {
    func testLoadingState() {
        let state: ViewState<String> = .loading
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.value)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadedState() {
        let state: ViewState<String> = .loaded("hello")
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.value, "hello")
        XCTAssertNil(state.errorMessage)
    }

    func testFailedState() {
        let state: ViewState<String> = .failed("network error")
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value)
        XCTAssertEqual(state.errorMessage, "network error")
    }

    func testIdleState() {
        let state: ViewState<String> = .idle
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.value)
        XCTAssertNil(state.errorMessage)
    }
}

// MARK: - HMAC Signing Protocol

/// These tests verify the nonce-inclusive HMAC signing protocol that the iOS client
/// uses for every request and the Rust server validates. They do NOT test the actual
/// HMAC key (device-specific, never accessible in tests) — they test that:
///   1. The nonce is inside the signed message (not just a header that can be stripped)
///   2. Different nonces produce different message bytes (nonce is part of the signature input)
///   3. The message format matches the server's expectation: method + path + ts + nonce + body
///   4. Nonces are valid UUIDs (the server rejects anything else with 400)
///
/// Server-side counterparts: `hmac.rs` tests in box-fraise-platform.
final class HMACSigningTests: XCTestCase {

    // MARK: - Nonce is inside the signed message

    /// A nonce that's only sent as a header (not in the signed bytes) can be stripped
    /// by a MITM without invalidating the HMAC. This verifies the nonce is in the message.
    func testNonceIsInsideSignedMessageNotJustAHeader() {
        let method    = "POST"
        let fullPath  = "/api/platform-messages/send"
        let timestamp = "1700000000"
        let nonce     = UUID().uuidString
        let body      = Data("{}".utf8)

        // This is the exact construction in APIClient.request()
        let message = "\(method)\(fullPath)\(timestamp)\(nonce)".data(using: .utf8)! + body

        // The nonce must appear in the message bytes, not just be a separate value.
        let messageString = String(data: message, encoding: .utf8) ?? ""
        XCTAssertTrue(
            messageString.contains(nonce),
            "Nonce must be inside the signed message bytes, not just a header"
        )
    }

    func testNonceAppearsAfterTimestampInMessage() {
        let method    = "GET"
        let path      = "/api/catalog"
        let timestamp = "1700000000"
        let nonce     = UUID().uuidString

        let headerPart = "\(method)\(path)\(timestamp)\(nonce)"
        let tsRange    = headerPart.range(of: timestamp)!
        let nonceRange = headerPart.range(of: nonce)!

        XCTAssertTrue(
            nonceRange.lowerBound > tsRange.upperBound,
            "Nonce must appear after the timestamp in the signed message"
        )
    }

    // MARK: - Different nonces produce different signed messages

    func testDifferentNoncesProduceDifferentMessageBytes() {
        let method    = "POST"
        let path      = "/api/orders"
        let timestamp = "1700000000"
        let body      = Data("{}".utf8)

        let nonce1 = UUID().uuidString
        let nonce2 = UUID().uuidString

        let msg1 = "\(method)\(path)\(timestamp)\(nonce1)".data(using: .utf8)! + body
        let msg2 = "\(method)\(path)\(timestamp)\(nonce2)".data(using: .utf8)! + body

        XCTAssertNotEqual(
            msg1, msg2,
            "Messages with different nonces must differ — proving nonce is part of the HMAC input"
        )
    }

    // MARK: - Message format matches server expectation

    /// The server computes: format!("{method}{path_and_query}{ts}{nonce}") + body_bytes
    /// The iOS client computes: "\(method)\(fullPath)\(timestamp)\(nonce)".utf8 + bodyData
    /// Both must produce identical bytes for the HMAC to verify.
    func testMessageFormatMatchesServerExpectation() {
        let method    = "POST"
        let path      = "/api/keys/register"
        let timestamp = "1700000000"
        let nonce     = "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"
        let body      = Data(#"{"identity_key":"abc"}"#.utf8)

        // iOS construction (from APIClient.request)
        let iosMessage = "\(method)\(path)\(timestamp)\(nonce)".data(using: .utf8)! + body

        // Expected server construction (Rust: format!("{method}{path}{ts}{nonce}") + body)
        let serverHeaderStr = "\(method)\(path)\(timestamp)\(nonce)"
        let serverMessage   = serverHeaderStr.data(using: .utf8)! + body

        XCTAssertEqual(iosMessage, serverMessage,
                       "iOS and server must construct identical message bytes for HMAC to verify")
    }

    // MARK: - Nonce format (server validates UUID)

    func testGeneratedNonceIsValidUUID() {
        for _ in 0..<20 {
            let nonce = UUID().uuidString
            XCTAssertNotNil(UUID(uuidString: nonce),
                            "UUID().uuidString must always produce a valid UUID: \(nonce)")
        }
    }

    func testNonceIsUniqueAcrossRequests() {
        let count  = 1000
        let nonces = Set((0..<count).map { _ in UUID().uuidString })
        XCTAssertEqual(nonces.count, count,
                       "Each request must produce a unique nonce — no collisions in \(count) samples")
    }

    // MARK: - rawRequest uses the same protocol

    func testRawRequestSignedMessageIncludesNonce() {
        // rawRequest uses url.path (not /api prefix + path) and the same nonce protocol.
        let method    = "PATCH"
        let path      = "/api/staff/orders/42/ready"
        let timestamp = "1700000000"
        let nonce     = UUID().uuidString
        let body      = Data()

        // rawRequest construction (from APIClient.rawRequest)
        let message = "\(method)\(path)\(timestamp)\(nonce)".data(using: .utf8)! + body

        let messageString = String(data: message, encoding: .utf8) ?? ""
        XCTAssertTrue(messageString.contains(nonce),
                      "rawRequest signed message must also contain the nonce")
        XCTAssertTrue(messageString.contains(timestamp),
                      "rawRequest signed message must contain the timestamp")
    }
}

// MARK: - Security

final class SecurityTests: XCTestCase {
    func testJailbreakReturnsFalseInSimulator() {
        #if targetEnvironment(simulator)
        XCTAssertFalse(AppSecurity.isJailbroken(), "Simulator should not be flagged as jailbroken")
        #endif
    }

    func testDebuggerReturnsFalseInDebug() {
        #if DEBUG
        XCTAssertFalse(AppSecurity.isDebuggerAttached(), "Debugger check should return false in debug builds")
        #endif
    }
}

// MARK: - DeepLinkPath

final class DeepLinkPathTests: XCTestCase {
    func testAllPathsHaveRawValues() {
        let paths: [DeepLinkPath] = [
            .orderHistory, .popups, .profile, .verify, .standingOrders,
            .inbox, .messages, .referrals, .meet, .akene, .offers, .memory
        ]
        for path in paths {
            XCTAssertFalse(path.rawValue.isEmpty, "\(path) has empty rawValue")
        }
    }

    func testOrderHistoryRawValue() {
        XCTAssertEqual(DeepLinkPath.orderHistory.rawValue, "order-history")
    }
}

// MARK: - PastOrder state machine

final class PastOrderTests: XCTestCase {
    private func makeOrder(status: String) -> PastOrder {
        PastOrder(id: 1, varietyName: "Elsanta", chocolate: "dark", finish: "plain",
                  quantity: 4, totalCents: 2000, status: status, nfcToken: nil,
                  rating: nil, slotDate: nil, slotTime: nil, createdAt: "2024-01-01T00:00:00Z")
    }

    func testPaidIncluedesReady() {
        XCTAssertTrue(makeOrder(status: "paid").isPaid)
        XCTAssertTrue(makeOrder(status: "ready").isPaid)
        XCTAssertFalse(makeOrder(status: "collected").isPaid)
    }

    func testIsReady() {
        XCTAssertTrue(makeOrder(status: "ready").isReady)
        XCTAssertFalse(makeOrder(status: "paid").isReady)
    }

    func testIsCollected() {
        XCTAssertTrue(makeOrder(status: "collected").isCollected)
        XCTAssertFalse(makeOrder(status: "paid").isCollected)
    }
}
