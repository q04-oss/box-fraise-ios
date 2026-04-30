import Foundation
import CoreLocation

// MARK: - String helpers

private extension String {
    // Converts an empty string to nil so optional-chaining reads naturally at call sites.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Price formatting

private protocol PricedItem { var priceCents: Int { get } }
private extension PricedItem {
    var priceFormatted: String { String(format: "CA$%.2f", Double(priceCents) / 100.0) }
}

// MARK: - Domain enumerations

enum MessageType: String, Codable, Sendable {
    case text, variety, popup, node, broadcast, official
    case other
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MessageType(rawValue: raw) ?? .other
    }
}

enum BusinessType: String, Codable, Sendable {
    case collection, partner
    case other
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BusinessType(rawValue: raw) ?? .other
    }
}

enum FraiseObjectType: String, Codable, Sendable {
    case variety, popup, node
    case other
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FraiseObjectType(rawValue: raw) ?? .other
    }
}

// MARK: - Business

struct Business: Codable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let type: BusinessType
    let description: String?
    let hours: String?
    let neighbourhood: String?
    let city: String?
    let approvedByAdmin: Bool?
    let locationId: Int?
    let slug: String?

    var isApproved: Bool     { approvedByAdmin ?? false }
    var isCollection: Bool   { type == .collection }
    // Returns nil when neither city nor neighbourhood is known — callers decide how to handle absence.
    // Unapproved businesses are shown on the map as ghost pins — visible but not orderable.
    var displayCity: String? { city ?? neighbourhood }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Auth

struct AuthResponse: Codable {
    let token: FraiseToken
    let userId: Int
    let displayName: String?
    let verified: Bool?
}

struct BoxUser: Codable {
    let id: Int
    let displayName: String?
    let verified: Bool
    let isShop: Bool
    let fraiseChatEmail: String?
    let currentStreakWeeks: Int?
    let socialTier: String?
    let status: String?

    var initial: String {
        guard let name = displayName, let first = name.first else { return "·" }
        return String(first).uppercased()
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, verified, isShop, fraiseChatEmail
        case currentStreakWeeks, socialTier, status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(Int.self, forKey: .id)
        displayName      = try c.decodeIfPresent(String.self, forKey: .displayName)
        verified         = try c.decodeIfPresent(Bool.self,   forKey: .verified)         ?? false
        isShop           = try c.decodeIfPresent(Bool.self,   forKey: .isShop)           ?? false
        fraiseChatEmail  = try c.decodeIfPresent(String.self, forKey: .fraiseChatEmail)
        currentStreakWeeks = try c.decodeIfPresent(Int.self,  forKey: .currentStreakWeeks)
        socialTier       = try c.decodeIfPresent(String.self, forKey: .socialTier)
        status           = try c.decodeIfPresent(String.self, forKey: .status)
    }

    init(id: Int, displayName: String?, verified: Bool, isShop: Bool,
         fraiseChatEmail: String?, currentStreakWeeks: Int?, socialTier: String?, status: String?) {
        self.id = id; self.displayName = displayName; self.verified = verified
        self.isShop = isShop; self.fraiseChatEmail = fraiseChatEmail
        self.currentStreakWeeks = currentStreakWeeks; self.socialTier = socialTier
        self.status = status
    }
}

// MARK: - Popup

struct FraisePopup: Codable, Identifiable, PricedItem {
    let id: Int
    let title: String
    let description: String?
    let priceCents: Int
    let minSeats: Int
    let maxSeats: Int
    let seatsClaimed: Int
    let status: String
    let eventDate: String?
    let businessName: String
    let businessSlug: String

    var isOpen: Bool         { status == "open" || status == "threshold_met" }
    var isConfirmed: Bool    { status == "confirmed" }
    var isThresholdMet: Bool { status == "threshold_met" }
    var isCancelled: Bool    { status == "cancelled" }
    var isClosed: Bool       { status == "closed" }
    // 0.0 → 1.0, clamped. Drives the progress bar fill animation in PopupsPanel.
    var thresholdPct: Double { minSeats > 0 ? min(1.0, Double(seatsClaimed) / Double(minSeats)) : 0 }
}

// MARK: - Ordering

struct Variety: Codable, Identifiable, PricedItem {
    let id: Int
    let name: String
    let description: String?
    let priceCents: Int
    let active: Bool?
    // Server omits 'active' on legacy records added before the field existed — treat absence as active.
    var isActive: Bool { active ?? true }
}

struct OrderState {
    var varietyId: Int?
    var varietyName: String?
    var priceCents: Int?
    var chocolate: String?
    var chocolateName: String?
    var finish: String?
    var finishName: String?
    var quantity: Int = 4

    var totalCents: Int  { (priceCents ?? 0) * quantity }
    var isComplete: Bool { varietyId != nil && chocolate != nil && finish != nil }

    mutating func reset() {
        varietyId = nil; varietyName = nil; priceCents = nil
        chocolate = nil; chocolateName = nil
        finish = nil;    finishName = nil
        quantity = 4
    }
}

struct OrderResponse: Codable {
    let id: Int
    let clientSecret: String
}

struct ConfirmedOrder: Codable {
    let id: Int
    let status: String
    let varietyName: String?
    let queuedBoxes: Int?
    let minQuantity: Int?
    let deliveryDate: String?
}

struct UserSocialAccess: Codable {
    let active: Bool?
    let tier: String?
    let bankDays: Int?
    let lifetimeDays: Int?
}

struct OrderReceipt: Codable {
    let id: Int
    let varietyName: String?
    let locationName: String?
    let createdAt: String?
    let nfcToken: String?
    let worker: ReceiptWorker?
    let seasonPatron: ReceiptPatron?
}

struct ReceiptWorker: Codable {
    let id: Int
    let displayName: String?
}

struct ReceiptPatron: Codable {
    let displayName: String?
    let userId: Int?
}

let CHOCOLATES: [(id: String, name: String)] = [
    ("dark",  "dark"),
    ("milk",  "milk"),
    ("white", "white"),
    ("none",  "no chocolate"),
]

let FINISHES: [(id: String, name: String)] = [
    ("plain",      "plain"),
    ("gold_dust",  "gold dust"),
    ("sprinkles",  "sprinkles"),
    ("sea_salt",   "sea salt"),
]

// MARK: - Order History

enum PastOrderStatus: String, Codable, Sendable {
    case paid, ready, preparing, collected, cancelled
    case other
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PastOrderStatus(rawValue: raw) ?? .other
    }
}

struct PastOrder: Codable, Identifiable {
    let id: Int
    let varietyName: String
    let chocolate: String
    let finish: String
    let quantity: Int
    let totalCents: Int
    let status: String
    let nfcToken: String?
    let rating: Int?
    let slotDate: String?
    let slotTime: String?
    let createdAt: String

    var totalFormatted: String  { String(format: "CA$%.2f", Double(totalCents) / 100.0) }
    // Slot is shown as "Mon Mar 15 · 7:00 PM" when both date and time are present.
    var formattedSlot: String?  { [slotDate, slotTime].compactMap { $0 }.joined(separator: " · ").nilIfEmpty }
    var isReady: Bool           { status == PastOrderStatus.ready.rawValue }
    var isPaid: Bool            { status == PastOrderStatus.paid.rawValue || isReady }
    var isCollected: Bool       { status == PastOrderStatus.collected.rawValue }
}

// MARK: - Staff Order

struct StaffOrder: Codable, Identifiable {
    let id: Int
    let customerEmail: String?
    let varietyName: String?
    let chocolate: String?
    let finish: String?
    let quantity: Int
    let totalCents: Int?
    let status: String
    let nfcToken: String?
    let slotDate: String?
    let slotTime: String?

    var summary: String {
        [varietyName, chocolate, finish].compactMap { $0 }.joined(separator: " · ").lowercased()
    }
}

// MARK: - NFC

// Shared provenance fields between first-scan and re-scan results.
struct NFCProvenance: Codable {
    let farm: String?
    let harvestDate: String?
    let batchNotes: String?
}

struct NFCVerifyResult: Codable {
    let verified: Bool
    let varietyName: String?
    let quantity: Int?
    let farm: String?
    let harvestDate: String?
    let fraiseChatEmail: String?
    let isDj: Bool?
    let unlocked: [String]?
    let tier: String?
    let bankDays: Int?
    let creditsAddedDays: Int?
    let lifetimeDays: Int?
    let streakWeeks: Int?
    let streakMilestone: Bool?
    let businessUserCode: String?
    let businessName: String?

    var provenance: NFCProvenance { NFCProvenance(farm: farm, harvestDate: harvestDate, batchNotes: nil) }
}

struct NFCReorderResult: Codable {
    let varietyName: String?
    let farm: String?
    let harvestDate: String?
    let quantity: Int?
    let orderCount: Int?
    let collectifPickupsToday: Int?
    let collectifMemberNames: [String]?
    let batchDeliveryDate: String?
    let batchNotes: String?
    let lastVariety: NFCLastVariety?
    let nextStandingOrder: NFCNextOrder?

    var provenance: NFCProvenance { NFCProvenance(farm: farm, harvestDate: harvestDate, batchNotes: batchNotes) }
}

struct NFCLastVariety: Codable {
    let name: String?
    let farm: String?
    let harvestDate: String?
}

struct NFCNextOrder: Codable {
    let varietyName: String?
    let daysUntil: Int?
}

// MARK: - Walk-in

struct WalkInItem: Codable, Identifiable, PricedItem {
    let id: Int
    let name: String
    let priceCents: Int
    let stockRemaining: Int?
}

// MARK: - Connections / Met

struct MeetingToken: Codable {
    let token: String
    let expiresIn: Int
}

struct PendingConnection: Codable, Identifiable {
    let id: Int
    let metAt: String
    let expiresAt: String
    let theirName: String?
    let theirCode: String?
    let iApproved: Bool
}

struct FraiseContact: Codable, Identifiable {
    let id: Int
    // contactId is the user ID of the contact; id is the connection record ID.
    let contactId: Int?
    let connectedAt: String
    let metAt: String?
    let name: String?
    let userCode: String?
    let verified: Bool?

    // Resolves the user ID without requiring callers to handle the id/contactId ambiguity.
    var resolvedContactId: Int { contactId ?? id }
}

// MARK: - Platform messaging

struct MessageThread: Codable, Identifiable {
    let contactId: Int
    let name: String?
    let userCode: String?
    let lastMessageId: Int?
    let lastMessageAt: String?
    let lastEncrypted: String?
    let lastType: String?
    let lastSenderId: Int?
    let unreadCount: Int
    let metAt: String?
    let isShop: Bool
    let isDorotka: Bool
    let contactStatus: String?

    var id: Int { contactId }
    var isBusiness: Bool      { isShop }
    var isDorotkaThread: Bool  { isDorotka }
    // The three thread categories are mutually exclusive and exhaustive.
    var isPersonalThread: Bool { !isBusiness && !isDorotkaThread }
    // Server-computed — avoids fetching all messages just to count unread. Updated on markThreadRead().
    var hasUnread: Bool        { unreadCount > 0 }

    private enum CodingKeys: String, CodingKey {
        case contactId, name, userCode, lastMessageId, lastMessageAt, lastEncrypted
        case lastType, lastSenderId, unreadCount, metAt, isShop, isDorotka, contactStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        contactId      = try c.decode(Int.self,              forKey: .contactId)
        name           = try c.decodeIfPresent(String.self,  forKey: .name)
        userCode       = try c.decodeIfPresent(String.self,  forKey: .userCode)
        lastMessageId  = try c.decodeIfPresent(Int.self,     forKey: .lastMessageId)
        lastMessageAt  = try c.decodeIfPresent(String.self,  forKey: .lastMessageAt)
        lastEncrypted  = try c.decodeIfPresent(String.self,  forKey: .lastEncrypted)
        lastType       = try c.decodeIfPresent(String.self,  forKey: .lastType)
        lastSenderId   = try c.decodeIfPresent(Int.self,     forKey: .lastSenderId)
        unreadCount    = try c.decode(Int.self,              forKey: .unreadCount)
        metAt          = try c.decodeIfPresent(String.self,  forKey: .metAt)
        isShop         = try c.decodeIfPresent(Bool.self,    forKey: .isShop)    ?? false
        isDorotka      = try c.decodeIfPresent(Bool.self,    forKey: .isDorotka) ?? false
        contactStatus  = try c.decodeIfPresent(String.self,  forKey: .contactStatus)
    }

    init(contactId: Int, name: String?, userCode: String?,
         lastMessageId: Int?, lastMessageAt: String?,
         lastEncrypted: String?, lastType: String?, lastSenderId: Int?,
         unreadCount: Int, metAt: String?,
         isShop: Bool, isDorotka: Bool, contactStatus: String?) {
        self.contactId = contactId; self.name = name; self.userCode = userCode
        self.lastMessageId = lastMessageId; self.lastMessageAt = lastMessageAt
        self.lastEncrypted = lastEncrypted; self.lastType = lastType
        self.lastSenderId = lastSenderId; self.unreadCount = unreadCount
        self.metAt = metAt; self.isShop = isShop; self.isDorotka = isDorotka
        self.contactStatus = contactStatus
    }
}

// Pairs a message ID with its display snippet — enforces the invariant that
// both fields are present when a reply context exists.
struct ReplyContext: Sendable {
    let messageId: Int
    let snippet: String
}

struct PlatformMessage: Codable, Identifiable {
    let id: Int
    let senderId: Int
    let recipientId: Int
    let encryptedBody: String
    let x3dhSenderKey: String?
    // Present when the sender used a one-time prekey during X3DH — consumed once by the recipient.
    let oneTimePreKeyId: Int?
    let messageType: String
    let fraiseObject: FraiseObject?
    let sentAt: String
    let deliveredAt: String?
    let readAt: String?
    let expiresAt: String?
    let replyToId: Int?
    let replyToSnippet: String?

    var reply: ReplyContext? {
        guard let id = replyToId, let snippet = replyToSnippet else { return nil }
        return ReplyContext(messageId: id, snippet: snippet)
    }
}

struct FraiseObject: Codable {
    let type: FraiseObjectType
    let id: Int?
    let name: String?
    let detail: String?
    let priceCents: Int?
}

// Signal prekey material — must never appear in logs or crash reports.
struct UserKeyBundle: Codable, CustomDebugStringConvertible {
    let userId: Int
    let identityKey: String
    let identitySigningKey: String?       // Ed25519 public key; nil if server not yet updated
    let signedPreKey: String
    let signedPreKeySignature: String
    let oneTimePreKey: String?
    let oneTimePreKeyId: Int?

    var debugDescription: String { "UserKeyBundle(userId: \(userId), [key material redacted])" }
}

// MARK: - Fraise inbox (legacy — superseded by MessagesPanel)

struct FraiseMessage: Codable, Identifiable {
    let id: Int
    let fromEmail: String
    let fromName: String?
    let subject: String?
    let body: String
    let receivedAt: String
    let readAt: String?

    var isRead: Bool { readAt != nil }
    var senderLabel: String { fromName ?? fromEmail }
}

// MARK: - Referrals

struct ReferralInfo: Codable {
    let code: String?
    let referralUrl: String?
    let referrals: [ReferralEntry]
}

struct ReferralEntry: Codable, Identifiable {
    let id: Int
    let refereeName: String?
    let createdAt: String
    let completedAt: String?

    var isCompleted: Bool { completedAt != nil }
}

// MARK: - Standing orders

struct StandingOrder: Codable, Identifiable {
    let id: Int
    let varietyName: String?
    let locationName: String?
    let quantity: Int
    let chocolate: String
    let finish: String
    let status: String

    // active / paused / cancelled are the only server-sent values. Anything else is a server bug.
    var isActive:    Bool { status == "active" }
    var isPaused:    Bool { status == "paused" }
    var isCancelled: Bool { status == "cancelled" }
}

// MARK: - Akène

struct AkeneProfile: Codable {
    let akeneHeld: Int
    let eventsAttended: Int
    let rankScore: Int
    let rankPosition: Int?
    let totalHolders: Int?
}

struct AkeneLeaderboardEntry: Codable, Identifiable {
    let displayName: String?
    let akeneHeld: Int
    let eventsAttended: Int
    let rankScore: Int
    let rankPosition: Int

    var id: Int { rankPosition }
}

struct AkeneInvitation: Codable, Identifiable {
    let id: Int
    let status: String        // your RSVP: pending | accepted | declined | waitlisted
    let sentAt: String
    let expiresAt: String?
    let respondedAt: String?
    let eventId: Int
    let title: String
    let description: String?
    let eventDate: String?
    let capacity: Int
    let acceptedCount: Int?
    let eventStatus: String   // event lifecycle: inviting | seated | confirmed | completed
    let businessName: String?

    // MARK: Your RSVP status
    var isPending:    Bool { status == "pending" }
    var isAccepted:   Bool { status == "accepted" }
    var isDeclined:   Bool { status == "declined" }
    var isWaitlisted: Bool { status == "waitlisted" }

    // MARK: Event lifecycle status
    var isSeated:     Bool { eventStatus == "seated" }
    var isConfirmed:  Bool { eventStatus == "confirmed" }
    var isCompleted:  Bool { eventStatus == "completed" }

    // MARK: Availability
    var seatsLeft:    Int  { capacity - (acceptedCount ?? 0) }
    var isFull:       Bool { seatsLeft <= 0 }

    // MARK: Timing
    // Fail-closed: a non-nil but unparseable expiresAt is treated as expired rather than unexpired,
    // so a corrupt date string never keeps a stale invitation visible.
    var isExpired: Bool {
        guard let iso = expiresAt else { return false }         // nil = no expiry
        guard let date = FraiseDateFormatter.date(from: iso) else { return true } // unparseable = expired
        return date < Date()
    }

    // MARK: Display
    /// Single human-readable status for cards and labels — avoids scattered inline switches.
    var displayStatus: String {
        if isWaitlisted { return "waitlisted" }
        if isAccepted   { return isCompleted ? "attended" : "accepted" }
        if isDeclined   { return "declined" }
        if isExpired    { return "expired" }
        return "invited"
    }
}

struct AkeneEventDetail: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let eventDate: String?
    let capacity: Int
    let acceptedCount: Int
    let status: String
    let businessName: String?

    var seatsLeft: Int { capacity - acceptedCount }
    var isFull: Bool   { seatsLeft <= 0 }
}

struct AkeneAttendee: Codable, Identifiable {
    let id: Int
    let displayName: String?
    let akeneHeld: Int
    let eventsAttended: Int
    let rankPosition: Int
}

struct AkeneHolderProfile: Codable {
    let displayName: String?
    let akeneHeld: Int
    let eventsAttended: Int
    let rankScore: Int
    let rankPosition: Int
    let totalHolders: Int?
}

struct AkenePurchaseResponse: Codable {
    let clientSecret: String
    let quantity: Int
    let amountCents: Int
}

struct AkenePurchaseRecord: Codable, Identifiable {
    let id: Int
    let quantity: Int
    let amountCents: Int
    let purchasedAt: String
}

struct AkeneMyEvent: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String?
    let eventDate: String?
    let capacity: Int
    let acceptedCount: Int
    let waitlistCount: Int?
    let status: String
    let createdAt: String?

    var seatsLeft:   Int  { capacity - acceptedCount }
    var isSeated:    Bool { status == "seated" }
    var isConfirmed: Bool { status == "confirmed" }
    var isCompleted: Bool { status == "completed" }
}

// MARK: - Date nights & promotions

struct DateInvitation: Codable, Identifiable {
    let id: Int
    let status: String
    let sentAt: String
    let openedAt: String?
    let feeCents: Int
    let offerId: Int
    let title: String
    let description: String?
    let eventDate: String
    let businessName: String?
    let businessAddress: String?
    let businessNeighbourhood: String?

    var isUnopened: Bool { openedAt == nil }
    var isOpened:  Bool { openedAt != nil }
    var isPending:  Bool { status == "pending" || status == "opened" }
    var isDeclined: Bool { status == "declined" }
    var isMatched:  Bool { status == "matched" }
}

struct MemoryRequest: Codable, Identifiable {
    let id: Int
    let matchId: Int
    let eventDate: String
    let theirName: String?
    let offerTitle: String?
    let businessName: String?
}

struct PromotionDelivery: Codable, Identifiable {
    let id: Int
    let deliveredAt: String
    let readAt: String?
    let feeCents: Int
    let promotionId: Int
    let title: String
    let body: String
    let businessName: String?

    var isUnread: Bool { readAt == nil }
}

struct UserEarnings: Codable {
    let balanceCents: Int
    struct Entry: Codable, Identifiable {
        let id: Int
        let sourceType: String
        let amountCents: Int
        let createdAt: String
    }
    let history: [Entry]
}

struct BusinessDateStats: Codable {
    let memoriesCount: Int
}

// MARK: - Panel

enum Panel: Equatable, CustomStringConvertible {
    case home, auth, profile, popups, order, orderHistory, staff, nfcVerify, walkIn
    case standingOrders, messages, referrals, meet, akene
    case partnerDetail(Business)
    case loyalty(Business)

    // Used as the identity value for SwiftUI panel transitions — must be unique per case.
    // Adding a new Panel case without updating description causes silent transition identity collisions.
    var description: String {
        switch self {
        case .home:                     return "home"
        case .auth:                     return "auth"
        case .profile:                  return "profile"
        case .popups:                   return "popups"
        case .order:                    return "order"
        case .orderHistory:             return "orderHistory"
        case .staff:                    return "staff"
        case .nfcVerify:                return "nfcVerify"
        case .walkIn:                   return "walkIn"
        case .standingOrders:           return "standingOrders"
        case .messages:                 return "messages"
        case .referrals:                return "referrals"
        case .meet:                     return "meet"
        case .akene:                    return "akene"
        case .partnerDetail(let b):     return "partnerDetail-\(b.id)"
        case .loyalty(let b):           return "loyalty-\(b.id)"
        }
    }

    static func == (lhs: Panel, rhs: Panel) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.auth, .auth), (.profile, .profile),
             (.popups, .popups), (.order, .order),
             (.orderHistory, .orderHistory), (.staff, .staff),
             (.nfcVerify, .nfcVerify), (.walkIn, .walkIn),
             (.standingOrders, .standingOrders),
             (.messages, .messages),
             (.referrals, .referrals),
             (.meet, .meet),
             (.akene, .akene):                                       return true
        case (.partnerDetail(let a), .partnerDetail(let b)):         return a.id == b.id
        case (.loyalty(let a),       .loyalty(let b)):               return a.id == b.id
        default: return false
        }
    }
}

// MARK: - Loyalty models

struct LoyaltyBalance: Codable {
    let steepsEarned:      Int
    let rewardsRedeemed:   Int
    let currentBalance:    Int
    let steepsPerReward:   Int
    let rewardDescription: String
    let steepsUntilReward: Int
    let rewardAvailable:   Bool
    let emailVerified:     Bool
}

struct LoyaltyEvent: Codable, Identifiable {
    let id:         Int
    let eventType:  String
    let source:     String
    let createdAt:  Date
}

struct LoyaltyQrToken: Codable {
    let token:     String
    let expiresAt: Date
}

// MARK: - Venue drinks models

struct VenueDrink: Codable, Identifiable {
    let id:          Int
    let name:        String
    let description: String
    let priceCents:  Int
    let category:    String
    let sortOrder:   Int

    var formattedPrice: String {
        let dollars = Double(priceCents) / 100
        return String(format: "$%.2f", dollars)
    }
}

struct VenueOrderResponse: Codable {
    let orderId:      Int
    let clientSecret: String
    let totalCents:   Int
}

struct CartItem: Identifiable, Equatable {
    let id:    Int  // drink.id
    let name:  String
    let price: Int  // priceCents
    var qty:   Int
}
