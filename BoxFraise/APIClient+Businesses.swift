import Foundation

extension APIClient {

    // MARK: - Businesses & popups

    func fetchBusinesses() async throws -> [Business] {
        try await request("/businesses")
    }

    func fetchPopups() async throws -> [FraisePopup] {
        let response: PopupsResponse = try await request("/fraise/popups")
        return response.popups
    }

    func joinPopup(id: Int, token: FraiseToken) async throws -> JoinResponse {
        try await request("/fraise/popups/\(id)/join", method: "POST", token: token)
    }

    func confirmPopupJoin(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/fraise/popups/\(id)/join/confirm",
                                               method: "POST", token: token)
    }

    func cancelPopup(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/fraise/popups/\(id)/cancel",
                                               method: "POST", token: token)
    }

    // MARK: - Varieties

    func fetchVarieties() async throws -> [Variety] {
        try await request("/varieties")
    }

    // MARK: - Referrals

    func fetchReferralInfo(token: FraiseToken) async throws -> ReferralInfo {
        try await request("/referrals/my-code", token: token)
    }

    func applyReferralCode(_ code: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/referrals/apply", method: "POST",
                                               body: ["code": code], token: token)
    }

    // MARK: - NFC

    func verifyNFC(token nfcToken: String, userToken: FraiseToken) async throws -> NFCVerifyResult {
        try await request("/verify/nfc", method: "POST",
                          body: ["nfc_token": nfcToken], token: userToken)
    }

    func verifyNFCReorder(token nfcToken: String, userToken: FraiseToken) async throws -> NFCReorderResult {
        try await request("/verify/reorder", method: "POST",
                          body: ["nfc_token": nfcToken], token: userToken)
    }

    // MARK: - App Attest

    // hmacKey: the device's per-device HMAC signing key (base64) so the server can
    // validate request signatures for this device independently of the App Attest assertion.
    func registerAttestation(keyID: String, attestation: Data, challenge: Data,
                              hmacKey: String, userToken: FraiseToken?) async throws {
        let _: OKResponse = try await request("/devices/attest", method: "POST", body: [
            "key_id":      keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge":   challenge.base64EncodedString(),
            "hmac_key":    hmacKey,
        ], token: userToken)
    }
}
