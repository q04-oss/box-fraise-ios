import Foundation
import CoreLocation

// MARK: - Price formatting

private protocol PricedItem { var priceCents: Int { get } }
private extension PricedItem {
    var priceFormatted: String { String(format: "CA$%.2f", Double(priceCents) / 100.0) }
}

// MARK: - Domain enumerations

enum BusinessType: String, Codable {
    case collection, partner
    case other
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BusinessType(rawValue: raw) ?? .other
    }
}

enum FraiseObjectType: String, Codable {
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

    var isApproved: Bool    { approvedByAdmin ?? false }
    var isCollection: Bool  { type == .collection }
    var displayCity: String { city ?? neighbourhood ?? "" }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Auth

struct AuthResponse: Codable {
    let token: String
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
        displayName.flatMap { $0.first.map(String.init) }?.uppercased() ?? "·"
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

struct FraisePopup: Codable, Identifiable {
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
    var thresholdPct: Double { minSeats > 0 ? min(1.0, Double(seatsClaimed) / Double(minSeats)) : 0 }
}

// MARK: - Ordering

struct Variety: Codable, Identifiable, PricedItem {
    let id: Int
    let name: String
    let description: String?
    let priceCents: Int
    let active: Bool?
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

    var totalFormatted: String { String(format: "CA$%.2f", Double(totalCents) / 100.0) }
    var isReady: Bool     { status == "ready" }
    var isPaid: Bool      { status == "paid" || isReady }
    var isCollected: Bool { status == "collected" }
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
    let contactId: Int?
    let connectedAt: String
    let metAt: String?
    let name: String?
    let userCode: String?
    let verified: Bool?
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
    var isDorotkaThread: Bool { isDorotka }
    var hasUnread: Bool       { unreadCount > 0 }

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
struct ReplyContext {
    let messageId: Int
    let snippet: String
}

struct PlatformMessage: Codable, Identifiable {
    let id: Int
    let senderId: Int
    let recipientId: Int
    let encryptedBody: String
    let x3dhSenderKey: String?
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

struct UserKeyBundle: Codable {
    let userId: Int
    let identityKey: String
    let signedPreKey: String
    let signedPreKeySignature: String
    let oneTimePreKey: String?
    let oneTimePreKeyId: Int?
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

    var isPending:    Bool { status == "pending" }
    var isAccepted:   Bool { status == "accepted" }
    var isDeclined:   Bool { status == "declined" }
    var isWaitlisted: Bool { status == "waitlisted" }
    var isCompleted:  Bool { eventStatus == "completed" }
    var isSeated:     Bool { eventStatus == "seated" }
    var isConfirmed:  Bool { eventStatus == "confirmed" }
    var seatsLeft:    Int  { capacity - (acceptedCount ?? 0) }
    var isFull:       Bool { seatsLeft <= 0 }
    // An invitation is expired when the response deadline has passed.
    var isExpired:    Bool {
        guard let iso = expiresAt, let date = FraiseDateFormatter.date(from: iso) else { return false }
        return date < Date()
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

    var description: String {
        switch self {
        case .home: return "home"
        case .auth: return "auth"
        case .profile: return "profile"
        case .popups: return "popups"
        case .order: return "order"
        case .orderHistory: return "orderHistory"
        case .staff: return "staff"
        case .nfcVerify: return "nfcVerify"
        case .walkIn: return "walkIn"
        case .standingOrders: return "standingOrders"
        case .messages: return "messages"
        case .referrals: return "referrals"
        case .meet: return "meet"
        case .akene: return "akene"
        case .partnerDetail(let b): return "partnerDetail((b.id))"
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
             (.akene, .akene): return true
        case (.partnerDetail(let a), .partnerDetail(let b)): return a.id == b.id
        default: return false
        }
    }
}
