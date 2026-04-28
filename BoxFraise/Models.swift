import Foundation
import CoreLocation

// MARK: - Price formatting

private protocol PricedItem { var priceCents: Int { get } }
private extension PricedItem {
    var priceFormatted: String { String(format: "CA$%.2f", Double(priceCents) / 100.0) }
}

// MARK: - Business

struct Business: Codable, Identifiable {
    let id: Int
    let name: String
    let address: String?
    let lat: Double?
    let lng: Double?
    let type: String
    let description: String?
    let hours: String?
    let neighbourhood: String?
    let city: String?
    let approvedByAdmin: Bool?
    let locationId: Int?

    var isApproved: Bool    { approvedByAdmin ?? false }
    var isCollection: Bool  { type == "collection" }
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
    let verified: Bool?
    let isShop: Bool?
    let fraiseChatEmail: String?
    let currentStreakWeeks: Int?
    let socialTier: String?
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
    var isPaid: Bool      { status == "paid" || status == "ready" }
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
    // Social / time bank
    let fraiseChatEmail: String?
    let isDj: Bool?
    let unlocked: [String]?
    let tier: String?
    let bankDays: Int?
    let creditsAddedDays: Int?
    let lifetimeDays: Int?
    let streakWeeks: Int?
    let streakMilestone: Bool?
    // Business node contact
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
    let isShop: Bool?
    let isDorotka: Bool?

    var id: Int { contactId }
    var isBusiness: Bool { isShop == true }
    var isDorotkaThread: Bool { isDorotka == true }
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
}

struct FraiseObject: Codable {
    let type: String
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

    var isActive: Bool { status == "active" }
}

// MARK: - Panel

enum Panel: Equatable {
    case home, auth, profile, popups, order, orderHistory, staff, nfcVerify, walkIn
    case standingOrders, messages, referrals, meet
    case partnerDetail(Business)

    static func == (lhs: Panel, rhs: Panel) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.auth, .auth), (.profile, .profile),
             (.popups, .popups), (.order, .order),
             (.orderHistory, .orderHistory), (.staff, .staff),
             (.nfcVerify, .nfcVerify), (.walkIn, .walkIn),
             (.standingOrders, .standingOrders),
             (.messages, .messages),
             (.referrals, .referrals),
             (.meet, .meet): return true
        case (.partnerDetail(let a), .partnerDetail(let b)): return a.id == b.id
        default: return false
        }
    }
}
