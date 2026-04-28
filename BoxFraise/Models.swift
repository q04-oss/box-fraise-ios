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
    var isPaid: Bool      { status == "paid" || status == "preparing" || status == "ready" }
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
}

// MARK: - Walk-in

struct WalkInItem: Codable, Identifiable, PricedItem {
    let id: Int
    let name: String
    let priceCents: Int
    let stockRemaining: Int?
}

// MARK: - Panel

enum Panel: Equatable {
    case home, auth, profile, popups, order, orderHistory, staff, nfcVerify, walkIn
    case partnerDetail(Business)

    static func == (lhs: Panel, rhs: Panel) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.auth, .auth), (.profile, .profile),
             (.popups, .popups), (.order, .order),
             (.orderHistory, .orderHistory), (.staff, .staff),
             (.nfcVerify, .nfcVerify), (.walkIn, .walkIn): return true
        case (.partnerDetail(let a), .partnerDetail(let b)): return a.id == b.id
        default: return false
        }
    }
}
