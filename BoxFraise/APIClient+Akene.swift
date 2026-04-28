import Foundation

extension APIClient {

    // MARK: - Akène profile & leaderboard

    func fetchAkeneProfile(token: FraiseToken) async throws -> AkeneProfile {
        try await request("/akene/my", token: token)
    }

    func fetchAkeneLeaderboard(token: FraiseToken) async throws -> [AkeneLeaderboardEntry] {
        try await request("/akene/leaderboard", token: token)
    }

    // MARK: - Purchase

    func purchaseAkene(quantity: Int, token: FraiseToken) async throws -> AkenePurchaseResponse {
        try await request("/akene/purchase", method: "POST", body: ["quantity": quantity], token: token)
    }

    func confirmAkenePurchase(paymentIntentId: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/akene/purchase/confirm", method: "POST",
                                               body: ["payment_intent_id": paymentIntentId], token: token)
    }

    func fetchAkenePurchases(token: FraiseToken) async throws -> [AkenePurchaseRecord] {
        try await request("/akene/purchases/mine", token: token)
    }

    // MARK: - Invitations

    func fetchAkeneInvitations(token: FraiseToken) async throws -> [AkeneInvitation] {
        try await request("/akene/invitations", token: token)
    }

    struct AcceptInvitationResponse: Decodable { let ok: Bool?; let waitlisted: Bool? }
    func acceptAkeneInvitation(id: Int, token: FraiseToken) async throws -> Bool {
        let r: AcceptInvitationResponse = try await request("/akene/invitations/\(id)/accept",
                                                            method: "POST", token: token)
        return r.waitlisted ?? false
    }

    func declineAkeneInvitation(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/akene/invitations/\(id)/decline",
                                               method: "POST", token: token)
    }

    // MARK: - Events

    func createAkeneEvent(title: String, description: String?, eventDate: String?,
                          capacity: Int, businessId: Int?, token: FraiseToken) async throws -> AkeneEventDetail {
        var body: [String: Any] = ["title": title, "capacity": capacity]
        if let d  = description { body["description"] = d }
        if let dt = eventDate   { body["event_date"]  = dt }
        if let bid = businessId { body["business_id"] = bid }
        return try await request("/akene/events", method: "POST", body: body, token: token)
    }

    func fetchAkeneEventDetail(id: Int, token: FraiseToken) async throws -> AkeneEventDetail {
        try await request("/akene/events/\(id)", token: token)
    }

    func fetchAkeneMyEvents(token: FraiseToken) async throws -> [AkeneMyEvent] {
        try await request("/akene/events/mine", token: token)
    }

    func setAkeneEventDate(eventId: Int, eventDate: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/akene/events/\(eventId)/set-date", method: "PATCH",
                                               body: ["event_date": eventDate], token: token)
    }

    func sendAkeneInvitations(eventId: Int, count: Int, token: FraiseToken) async throws -> Int {
        struct R: Decodable { let sent: Int }
        let r: R = try await request("/akene/events/\(eventId)/invite", method: "POST",
                                      body: ["count": count], token: token)
        return r.sent
    }

    func fetchAkeneAttendees(eventId: Int, token: FraiseToken) async throws -> [AkeneAttendee] {
        try await request("/akene/events/\(eventId)/attendees", token: token)
    }

    func fetchAkeneHolderProfile(userId: Int, token: FraiseToken) async throws -> AkeneHolderProfile {
        try await request("/akene/holders/\(userId)", token: token)
    }
}
