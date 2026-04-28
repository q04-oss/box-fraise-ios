import Foundation

extension APIClient {

    // MARK: - Date invitations

    func fetchDateInvitations(token: FraiseToken) async throws -> [DateInvitation] {
        try await request("/dates/invitations", token: token)
    }

    func openDateInvitation(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/invitations/\(id)/open",
                                               method: "POST", token: token)
    }

    func acceptDateInvitation(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/invitations/\(id)/accept",
                                               method: "POST", token: token)
    }

    func declineDateInvitation(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/invitations/\(id)/decline",
                                               method: "POST", token: token)
    }

    // MARK: - Memory requests

    func fetchMemoryRequests(token: FraiseToken) async throws -> [MemoryRequest] {
        try await request("/dates/memory", token: token)
    }

    func respondToMemory(id: Int, wants: Bool, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/memory/\(id)/respond", method: "POST",
                                               body: ["wants": wants], token: token)
    }

    // MARK: - Promotions

    func fetchPromotions(token: FraiseToken) async throws -> [PromotionDelivery] {
        try await request("/dates/promotions", token: token)
    }

    func readPromotion(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/promotions/\(id)/read",
                                               method: "POST", token: token)
    }

    // MARK: - Earnings

    func fetchEarnings(token: FraiseToken) async throws -> UserEarnings {
        try await request("/dates/earnings", token: token)
    }

    func fetchBusinessDateStats(businessId: Int) async throws -> BusinessDateStats {
        try await request("/dates/business/\(businessId)/stats")
    }
}
