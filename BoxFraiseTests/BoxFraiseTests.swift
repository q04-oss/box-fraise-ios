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
