import Foundation

extension APIClient {

    // MARK: - Signal key server

    /// Returns a random server-issued challenge for proof-of-possession signing.
    /// The client signs this with its Ed25519 identity key and returns the signature
    /// in publishKeys — proving it holds the private key before the server stores the public key.
    func fetchKeyChallenge(token: FraiseToken) async throws -> Data {
        struct ChallengeResponse: Decodable { let challenge: String }
        let r: ChallengeResponse = try await request("/keys/challenge", token: token)
        guard let data = Data(base64Encoded: r.challenge) else {
            throw APIError.serverError("invalid challenge encoding")
        }
        return data
    }

    func publishKeys(identityKey: String, identitySigningKey: String,
                     signedPreKey: String, signedPreKeySig: String,
                     challengeSig: String,
                     token: FraiseToken) async throws {
        let _: OKResponse = try await request("/keys/register", method: "POST", body: [
            "identityKey":        identityKey,
            "identitySigningKey": identitySigningKey,
            "signedPreKey":       signedPreKey,
            "signedPreKeySig":    signedPreKeySig,
            "challengeSig":       challengeSig,
        ], token: token)
    }

    /// Returns the number of one-time prekeys currently held by the server for this device.
    /// Used to decide whether replenishment is needed before the pool drains to zero.
    func fetchOneTimePreKeyCount(token: FraiseToken) async throws -> Int {
        struct OPKCountResponse: Decodable { let count: Int }
        let r: OPKCountResponse = try await request("/keys/one-time/count", token: token)
        return r.count
    }

    /// Uploads one-time prekeys. Each key is consumed exactly once during X3DH receive,
    /// enabling the strongest 4-DH variant. Server replenishes when count drops below 5.
    func uploadOneTimePreKeys(keys: [[String: Any]], token: FraiseToken) async throws {
        let _: OKResponse = try await request("/keys/one-time", method: "POST",
                                               body: ["keys": keys], token: token)
    }

    // Fetched once per contact on first message send. Consider caching with a 5-minute TTL
    // to reduce latency — key bundles change only when the contact reinstalls or rotates keys.
    func fetchKeyBundle(userId: Int, token: FraiseToken) async throws -> UserKeyBundle {
        try await request("/keys/bundle/\(userId)", token: token)
    }

    func fetchKeyBundleByCode(_ userCode: String, token: FraiseToken) async throws -> UserKeyBundle {
        try await request("/keys/bundle/by-code/\(userCode)", token: token)
    }

    // MARK: - Threads

    func fetchThreads(token: FraiseToken) async throws -> [MessageThread] {
        try await request("/platform-messages/threads", token: token)
    }

    func fetchThread(userCode: String, token: FraiseToken) async throws -> [PlatformMessage] {
        try await request("/platform-messages/thread/\(userCode)", token: token)
    }

    func fetchNewMessages(userCode: String, afterId: Int, token: FraiseToken) async throws -> [PlatformMessage] {
        try await request("/platform-messages/thread/\(userCode)/new?after_id=\(afterId)", token: token)
    }

    // MARK: - Send

    func sendMessage(recipientCode: String, encryptedBody: String, messageType: String = "text",
                     fraiseObject: FraiseObject? = nil, x3dhSenderKey: String? = nil,
                     expiresInDays: Int? = nil, replyToId: Int? = nil,
                     replyToSnippet: String? = nil, token: FraiseToken) async throws -> PlatformMessage {
        var body: [String: Any] = [
            "recipient_code": recipientCode,
            "encrypted_body": encryptedBody,
            "message_type":   messageType,
        ]
        if let obj = fraiseObject, let data = try? JSONEncoder().encode(obj),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            body["fraise_object"] = dict
        }
        if let key  = x3dhSenderKey  { body["x3dh_sender_key"]   = key }
        if let days = expiresInDays  { body["expires_in_days"]    = days }
        if let rid  = replyToId      { body["reply_to_id"]        = rid }
        if let snip = replyToSnippet { body["reply_to_snippet"]   = snip }
        return try await request("/platform-messages/send", method: "POST", body: body, token: token)
    }

    // Caller must encrypt the body before calling — plaintext must never reach the server.
    func broadcastMessage(encryptedBody: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/platform-messages/broadcast", method: "POST",
                                               body: ["encrypted_body": encryptedBody], token: token)
    }

    // MARK: - Read receipts / typing

    func markThreadDelivered(userCode: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/platform-messages/thread/\(userCode)/delivered",
                                               method: "POST", token: token)
    }

    func markThreadRead(userCode: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/platform-messages/thread/\(userCode)/read",
                                               method: "POST", token: token)
    }

    func sendTyping(toUserCode: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/platform-messages/thread/\(toUserCode)/typing",
                                               method: "POST", token: token)
    }

    func checkTyping(fromUserCode: String, token: FraiseToken) async throws -> Bool {
        struct TypingResponse: Decodable { let typing: Bool }
        let r: TypingResponse = try await request(
            "/platform-messages/thread/\(fromUserCode)/typing-status", token: token)
        return r.typing
    }

    // MARK: - Fraise inbox

    func fetchFraiseMessages(token: FraiseToken) async throws -> [FraiseMessage] {
        try await request("/fraise-chat/messages", token: token)
    }

    func markMessageRead(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/fraise-chat/messages/\(id)/read",
                                               method: "POST", token: token)
    }

    func deleteMessage(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/fraise-chat/messages/\(id)",
                                               method: "DELETE", token: token)
    }

    func addBusinessContact(businessCode: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/connections/business-contact", method: "POST",
                                               body: ["business_user_code": businessCode], token: token)
    }
}
