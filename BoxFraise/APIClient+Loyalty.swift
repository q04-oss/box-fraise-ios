import Foundation

extension APIClient {

    func fetchLoyaltyBalance(businessId: Int, token: FraiseToken) async throws -> LoyaltyBalance {
        try await request("/businesses/\(businessId)/loyalty", token: token)
    }

    func fetchLoyaltyHistory(businessId: Int, limit: Int = 20, token: FraiseToken) async throws -> [LoyaltyEvent] {
        try await request("/businesses/\(businessId)/loyalty/history?limit=\(limit)", token: token)
    }

    func fetchQrToken(businessId: Int, token: FraiseToken) async throws -> LoyaltyQrToken {
        try await request("/businesses/\(businessId)/loyalty/qr-token", token: token)
    }

    func resendVerificationEmail(token: FraiseToken) async throws {
        let _: OKResponse = try await request("/auth/resend-verification", method: "POST", token: token)
    }

    func redeemNFCSticker(uuid: String, token: FraiseToken) async throws -> NFCRedeemResponse {
        try await request("/nfc/redeem", method: "POST", body: ["sticker_uuid": uuid], token: token)
    }
}
