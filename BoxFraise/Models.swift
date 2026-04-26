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
        case businessName = "business_name"
        case businessSlug = "business_slug"
    }

    var isPending: Bool    { status == "pending" }
    var isAccepted: Bool   { status == "accepted" }
    var isConfirmed: Bool  { status == "confirmed" }
    var isDeclined: Bool   { status == "declined" }
    var isActive: Bool     { status != "declined" }
}

struct FraiseMemberPublic: Codable, Identifiable {
    let id: Int
    let name: String
    let standing: Int
    let eventsAttended: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, standing
        case eventsAttended = "events_attended"
        case createdAt      = "created_at"
    }
}

// MARK: - Response envelopes

struct InvitationsResponse: Codable {
    let invitations: [FraiseInvitation]
}

struct DirectoryResponse: Codable {
    let members: [FraiseMemberPublic]
}

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

struct CreditsConfirmResponse: Codable {
    let ok: Bool
    let creditsAdded: Int
    let creditBalance: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case creditsAdded  = "credits_added"
        case creditBalance = "credit_balance"
    }
}

struct AcceptResponse: Codable {
    let ok: Bool
    let creditBalance: Int
    let seatsClaimed: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case creditBalance = "credit_balance"
        case seatsClaimed  = "seats_claimed"
    }
}

struct DeclineResponse: Codable {
    let ok: Bool
    let creditReturned: Bool
    let creditBalance: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case creditReturned = "credit_returned"
        case creditBalance  = "credit_balance"
    }
}
