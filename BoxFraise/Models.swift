import Foundation
import CoreLocation

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

    enum CodingKeys: String, CodingKey {
        case id, name, address, lat, lng, type, description, hours, neighbourhood, city
        case approvedByAdmin = "approved_by_admin"
        case locationId = "location_id"
    }

    var isApproved: Bool { approvedByAdmin ?? false }
    var isCollection: Bool { type == "collection" }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var displayCity: String { city ?? neighbourhood ?? "" }
}

// MARK: - Auth

struct AuthResponse: Codable {
    let token: String
    let userId: Int
    let displayName: String?
    let verified: Bool?

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case displayName = "display_name"
        case verified
    }
}

struct BoxUser: Codable {
    let id: Int
    let displayName: String?
    let verified: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case verified
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

    enum CodingKeys: String, CodingKey {
        case id, title, description, status
        case priceCents   = "price_cents"
        case minSeats     = "min_seats"
        case maxSeats     = "max_seats"
        case seatsClaimed = "seats_claimed"
        case eventDate    = "event_date"
        case businessName = "business_name"
        case businessSlug = "business_slug"
    }

    var isOpen: Bool        { status == "open" || status == "threshold_met" }
    var isConfirmed: Bool   { status == "confirmed" }
    var isThresholdMet: Bool { status == "threshold_met" }
    var thresholdPct: Double { minSeats > 0 ? min(1.0, Double(seatsClaimed) / Double(minSeats)) : 0 }
    var priceFormatted: String { "CA$\(priceCents / 100)" }
}

// MARK: - Ordering

struct Variety: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let priceCents: Int
    let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, active
        case priceCents = "price_cents"
    }

    var priceFormatted: String { "CA$\(String(format: "%.2f", Double(priceCents) / 100))" }
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

    var totalCents: Int { (priceCents ?? 0) * quantity }
    var isComplete: Bool { varietyId != nil && chocolate != nil && finish != nil }

    mutating func reset() {
        varietyId = nil; varietyName = nil; priceCents = nil
        chocolate = nil; chocolateName = nil
        finish = nil; finishName = nil
        quantity = 4
    }
}

struct OrderResponse: Codable {
    let id: Int
    let clientSecret: String
    enum CodingKeys: String, CodingKey {
        case id
        case clientSecret = "client_secret"
    }
}

struct ConfirmedOrder: Codable {
    let id: Int
    let status: String
    let varietyName: String?
    enum CodingKeys: String, CodingKey {
        case id, status
        case varietyName = "variety_name"
    }
}

let CHOCOLATES: [(id: String, name: String)] = [
    ("dark",       "dark"),
    ("milk",       "milk"),
    ("white",      "white"),
    ("none",       "no chocolate"),
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

    enum CodingKeys: String, CodingKey {
        case id, chocolate, finish, quantity, status, rating
        case varietyName = "variety_name"
        case totalCents  = "total_cents"
        case nfcToken    = "nfc_token"
        case slotDate    = "slot_date"
        case slotTime    = "slot_time"
        case createdAt   = "created_at"
    }

    var totalFormatted: String { "CA$\(String(format: "%.2f", Double(totalCents) / 100))" }
    var isPaid: Bool { status == "paid" || status == "preparing" || status == "ready" }
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

    enum CodingKeys: String, CodingKey {
        case id, chocolate, finish, quantity, status
        case customerEmail = "customer_email"
        case varietyName   = "variety_name"
        case totalCents    = "total_cents"
        case nfcToken      = "nfc_token"
        case slotDate      = "slot_date"
        case slotTime      = "slot_time"
    }

    var summary: String {
        [varietyName, chocolate, finish].compactMap { $0 }.joined(separator: " · ").lowercased()
    }
}

// MARK: - NFC Verify Result

struct NFCVerifyResult: Codable {
    let verified: Bool
    let varietyName: String?
    let quantity: Int?
    let farm: String?
    let harvestDate: String?

    enum CodingKeys: String, CodingKey {
        case verified
        case varietyName = "variety_name"
        case quantity
        case farm
        case harvestDate = "harvest_date"
    }
}

// MARK: - Walk-in

struct WalkInToken: Codable {
    let id: Int
    let token: String
    let locationName: String
    let varietyName: String
    let priceCents: Int
    let stockRemaining: Int
    let claimed: Bool
    let allowsWalkin: Bool

    enum CodingKeys: String, CodingKey {
        case id, token, claimed
        case locationName   = "location_name"
        case varietyName    = "variety_name"
        case priceCents     = "price_cents"
        case stockRemaining = "stock_remaining"
        case allowsWalkin   = "allows_walkin"
    }

    var priceFormatted: String { "CA$\(String(format: "%.2f", Double(priceCents) / 100))" }
}

struct WalkInItem: Codable, Identifiable {
    let id: Int
    let name: String
    let priceCents: Int
    let stockRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case priceCents     = "price_cents"
        case stockRemaining = "stock_remaining"
    }

    var priceFormatted: String { "CA$\(String(format: "%.2f", Double(priceCents) / 100))" }
}

// MARK: - Panel

enum Panel: Equatable {
    case home
    case auth
    case profile
    case popups
    case order
    case orderHistory
    case staff
    case nfcVerify
    case walkIn
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
