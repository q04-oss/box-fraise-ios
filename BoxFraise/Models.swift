import Foundation

struct FraiseMember: Codable {
    let id: Int?
    let name: String
    let email: String
    let creditBalance: Int
    let creditsPurchased: Int
    let standing: Int?
    let eventsAttended: Int?
    let responseRate: Int?
    let createdAt: String?
    var token: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, token, standing
        case creditBalance    = "credit_balance"
        case creditsPurchased = "credits_purchased"
        case eventsAttended   = "events_attended"
        case responseRate     = "response_rate"
        case createdAt        = "created_at"
    }
}

struct FraiseInvitation: Codable, Identifiable {
    let id: Int
    let status: String
    let createdAt: String
    let respondedAt: String?
    let eventId: Int
    let title: String
    let description: String?
    let priceCents: Int
    let minSeats: Int
    let maxSeats: Int
    let seatsClaimed: Int
    let eventStatus: String
    let eventDate: String?
    let businessName: String
    let businessSlug: String

    enum CodingKeys: String, CodingKey {
        case id, status, title, description
        case createdAt    = "created_at"
        case respondedAt  = "responded_at"
        case eventId      = "event_id"
        case priceCents   = "price_cents"
        case minSeats     = "min_seats"
        case maxSeats     = "max_seats"
        case seatsClaimed = "seats_claimed"
        case eventStatus  = "event_status"
        case eventDate    = "event_date"
        case locationText = "location_text"
        case businessName = "business_name"
        case businessSlug = "business_slug"
    }

    let locationText: String?
    let lat: Double?
    let lng: Double?

    var isPending: Bool   { status == "pending" }
    var isAccepted: Bool  { status == "accepted" }
    var isConfirmed: Bool { status == "confirmed" }
    var isDeclined: Bool  { status == "declined" }
    var isActive: Bool    { !isDeclined }
}

// MARK: - Response types

struct CheckoutResponse: Codable {
    let clientSecret: String
    let amountCents: Int
    let credits: Int
    enum CodingKeys: String, CodingKey {
        case credits
        case clientSecret = "client_secret"
        case amountCents  = "amount_cents"
    }
}

