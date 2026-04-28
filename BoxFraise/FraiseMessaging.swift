import Foundation
import CryptoKit

// MARK: - Message cache (decrypted plaintext, in-process only)
//
// Intentionally NOT persisted. UserDefaults is an unencrypted on-disk plist
// included in iCloud/iTunes backups. Decrypted message content must never
// leave the process. Cache is lost on app restart; messages are re-decrypted
// from the server-stored ciphertext on next load.

enum MessageCache {
    private static let lock    = NSLock()
    private static var store:  [Int: String] = [:]
    private static let maxSize = 2000

    static func get(_ id: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[id]
    }

    static func set(_ id: Int, text: String) {
        lock.lock(); defer { lock.unlock() }
        store[id] = text
        if store.count > maxSize {
            let sorted = store.keys.sorted()
            sorted.prefix(store.count - 1800).forEach { store.removeValue(forKey: $0) }
        }
    }
}

// MARK: - Messaging coordinator

enum FraiseMessagingError: LocalizedError {
    case malformed, noSession, decryptionFailed

    var errorDescription: String? {
        switch self {
        case .malformed:         return "message format invalid"
        case .noSession:         return "no session established"
        case .decryptionFailed:  return "decryption failed"
        }
    }
}

final class FraiseMessaging {
    static let shared = FraiseMessaging()

    // MARK: - Key publishing

    func publishKeys(token: String) async throws {
        let identity  = MessagingKeyStore.identityKey
        let signedPre = MessagingKeyStore.signedPreKey
        let sig       = hmacSignature(signedPre: signedPre, identity: identity)
        try await APIClient.shared.publishKeys(
            identityKey:    identity.publicKeyBytes.base64EncodedString(),
            signedPreKey:   signedPre.publicKeyBytes.base64EncodedString(),
            signedPreKeySig: sig,
            token: token
        )
    }

    // MARK: - Encrypt (send path)

    /// Returns (wire, x3dhSenderKey, isFirstMessage)
    func encrypt(plaintext: String, forUserId contactUserId: Int, bundle: UserKeyBundle) throws -> (wire: String, x3dhSenderKey: String?, isFirst: Bool) {
        let isFirst = !MessagingKeyStore.hasSession(for: contactUserId)
        var state: RatchetState

        if isFirst {
            let identity  = MessagingKeyStore.identityKey
            let preBundle = PreKeyBundle(
                userId: bundle.userId,
                identityKey:            Data(base64Encoded: bundle.identityKey) ?? Data(),
                signedPreKey:           Data(base64Encoded: bundle.signedPreKey) ?? Data(),
                signedPreKeySignature:  Data(base64Encoded: bundle.signedPreKeySignature) ?? Data(),
                oneTimePreKey:          bundle.oneTimePreKey.flatMap { Data(base64Encoded: $0) },
                oneTimePreKeyId:        bundle.oneTimePreKeyId
            )
            let x3dh = try x3dhSend(senderIdentity: identity, recipientBundle: preBundle)
            state    = try initSendRatchet(masterSecret: x3dh.masterSecret, recipientPublicKey: preBundle.signedPreKey)
        } else {
            state = MessagingKeyStore.session(for: contactUserId)!
        }

        let (newState, encrypted) = try ratchetEncrypt(state: state, plaintext: plaintext)
        MessagingKeyStore.save(newState, for: contactUserId)

        let x3dhKey = isFirst
            ? MessagingKeyStore.identityKey.publicKeyBytes.base64EncodedString()
            : nil

        return (encrypted.toWire(), x3dhKey, isFirst)
    }

    // MARK: - Decrypt (receive path)

    func decrypt(message: PlatformMessage) throws -> String {
        if let cached = MessageCache.get(message.id) { return cached }

        guard let enc = EncryptedMessage.fromWire(message.encryptedBody) else {
            throw FraiseMessagingError.malformed
        }

        let senderId = message.senderId
        var state: RatchetState

        if let existing = MessagingKeyStore.session(for: senderId) {
            state = existing
        } else {
            // X3DH receive: need sender's identity key from first message
            guard let senderKeyStr = message.x3dhSenderKey,
                  let senderIdentityKey = Data(base64Encoded: senderKeyStr) else {
                throw FraiseMessagingError.noSession
            }
            let identity  = MessagingKeyStore.identityKey
            let signedPre = MessagingKeyStore.signedPreKey
            let masterSecret = try x3dhReceive(
                recipientIdentity:    identity,
                recipientSignedPreKey: signedPre,
                senderIdentityKey:    senderIdentityKey,
                senderEphemeralKey:   enc.ephemeralKey
            )
            state = initRecvRatchet(masterSecret: masterSecret, signedPreKey: signedPre)
        }

        do {
            let (newState, plaintext) = try ratchetDecrypt(state: state, message: enc)
            MessagingKeyStore.save(newState, for: senderId)
            MessageCache.set(message.id, text: plaintext)
            return plaintext
        } catch {
            throw FraiseMessagingError.decryptionFailed
        }
    }

    // MARK: - Private

    private func hmacSignature(signedPre: MessagingKeyPair, identity: MessagingKeyPair) -> String {
        let key = SymmetricKey(data: identity.privateKey.rawRepresentation)
        let mac = HMAC<SHA256>.authenticationCode(for: signedPre.publicKeyBytes, using: key)
        return Data(mac).base64EncodedString()
    }
}
