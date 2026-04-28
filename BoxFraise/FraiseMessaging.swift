// Signal Protocol end-to-end encryption:
//   • X3DH key exchange on the first message to a new contact — establishes a shared secret
//     using identity keys, signed prekeys, and one-time prekeys (when available).
//   • Double Ratchet for all subsequent messages — forward secrecy via per-message key derivation.
//     Old message keys are deleted after use; a compromised session does not expose past messages.
// All keys are generated and stored in-memory or in Keychain. They are never logged or persisted
// to UserDefaults, iCloud, or any unencrypted storage.

import Foundation
import CryptoKit
import os.log

// MARK: - Message cache (decrypted plaintext, in-process only)
//
// Intentionally NOT persisted. UserDefaults is an unencrypted on-disk plist
// included in iCloud/iTunes backups. Decrypted message content must never
// leave the process. Cache is lost on app restart; messages are re-decrypted
// from the server-stored ciphertext on next load.

enum MessageCache {
    private static let lock    = NSLock()
    private static var store:  [Int: String] = [:]
    private static var minKey: Int = Int.max  // Sentinel: updated to first inserted key on first set() call
    // 2000 entries × ~200 B average plaintext ≈ 400 KB in-process — well within
    // a typical iOS working-set budget. evictionTargetSize evicts a 200-entry batch on
    // each overflow so we pay one minKey scan per ~200 inserts, not per insert.
    private static let maxSize            = 2000
    private static let evictionTargetSize = 1800

    static func get(_ id: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[id]
    }

    static func set(_ id: Int, text: String) {
        lock.lock(); defer { lock.unlock() }
        if store[id] == nil && id < minKey { minKey = id }
        store[id] = text
        guard store.count > maxSize else { return }
        // Evict oldest IDs (lowest key) until we reach evictionTargetSize.
        var current = minKey
        while store.count > evictionTargetSize {
            if store.removeValue(forKey: current) != nil, current == minKey {
                minKey = store.keys.min() ?? Int.max
            }
            current += 1
        }
    }
}

// MARK: - Errors

enum FraiseMessagingError: LocalizedError {
    case malformed, noSession, decryptionFailed, publishFailed, identityKeyChanged, unverifiablePreKey

    var errorDescription: String? {
        switch self {
        case .malformed:           return "message format invalid"
        case .noSession:           return "no session established"
        case .decryptionFailed:    return "decryption failed"
        case .publishFailed:       return "key publication failed after retries"
        case .identityKeyChanged:  return "contact's encryption key has changed"
        case .unverifiablePreKey:  return "prekey signature verification required — server update pending"
        }
    }
}

// MARK: - Messaging coordinator (actor)
//
// Actor isolation serialises all encrypt/decrypt/publish operations — no two
// concurrent callers can interleave ratchet state reads and writes. The NSLock
// in MessagingKeyStore remains as a defence-in-depth guard for any future
// call site that bypasses the actor boundary.

actor FraiseMessaging {
    static let shared = FraiseMessaging()
    private init() {}

    private static let log = Logger(subsystem: "com.boxfraise.app", category: "messaging")

    // Signed prekeys rotate weekly. A compromised signed prekey cannot retroactively
    // decrypt past messages (forward secrecy via ratchet), but rotation limits the
    // window during which an attacker can establish new sessions under that key.
    private static let signedPreKeyRotationInterval: TimeInterval = 7 * 24 * 3600
    private static let signedPreKeyLastRotatedKey = "messaging.signed_pre_key_last_rotated"

    // OPKs are replenished when the server count drops below this threshold.
    // Without OPKs, new sessions fall back to 3-DH X3DH (no deniability property).
    private static let opkReplenishThreshold = 5
    private static let opkBatchSize          = 10

    // Flip to true once server ships identitySigningKey on all key bundles.
    // In strict mode, sessions cannot be established without signature verification —
    // any bundle missing identitySigningKey throws FraiseMessagingError.unverifiablePreKey.
    private static let requirePreKeyVerification = false

    // MARK: - Key publishing with retry

    /// Publishes public keys to the box fraise key server with exponential backoff.
    /// Rotates the signed prekey if it's older than 7 days.
    /// Uploads 10 one-time prekeys to enable full X3DH security.
    func publishPublicKeys(token: FraiseToken) async throws {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                try await _publishPublicKeys(token: token)
                Self.log.info("Key publication succeeded on attempt \(attempt + 1)")
                return
            } catch APIError.rateLimited(let retryAfter) {
                Self.log.warning("Key publication rate-limited — retrying after \(Int(retryAfter))s")
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            } catch {
                lastError = error
                if attempt < 3 {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
                    Self.log.warning("Key publication attempt \(attempt + 1) failed — retrying in \(attempt + 1)s")
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        Self.log.error("Key publication failed after 4 attempts")
        throw lastError ?? FraiseMessagingError.publishFailed
    }

    private func _publishPublicKeys(token: FraiseToken) async throws {
        // Prune sessions idle for more than 90 days — forward secrecy enforcement at rest.
        MessagingKeyStore.pruneExpiredSessions()

        // Rotate signed prekey if older than 7 days.
        let lastRotated = UserDefaults.standard.double(forKey: Self.signedPreKeyLastRotatedKey)
        let now = Date().timeIntervalSince1970
        if lastRotated == 0 || now - lastRotated > Self.signedPreKeyRotationInterval {
            MessagingKeyStore.rotateSignedPreKey()
            UserDefaults.standard.set(now, forKey: Self.signedPreKeyLastRotatedKey)
            Self.log.info("Signed prekey rotated")
        }

        let identity  = MessagingKeyStore.identityKey
        let signedPre = MessagingKeyStore.signedPreKey
        let sig       = try signPreKey(signedPre, with: identity)

        // Proof of possession: server issues a random challenge; we sign it with the
        // Ed25519 identity key before the server stores our public key. This prevents
        // a compromised server from registering arbitrary keys on behalf of any user —
        // an attacker without the private key cannot produce a valid signature.
        let challenge    = try await APIClient.shared.fetchKeyChallenge(token: token)
        let challengeSig = try identity.signingKey.signature(for: challenge)

        try await APIClient.shared.publishKeys(
            identityKey:        identity.publicKeyBytes.base64EncodedString(),
            identitySigningKey: identity.signingPublicKeyBytes.base64EncodedString(),
            signedPreKey:       signedPre.publicKeyBytes.base64EncodedString(),
            signedPreKeySig:    sig,
            challengeSig:       Data(challengeSig).base64EncodedString(),
            token: token
        )

        // Replenish one-time prekeys if the server count is below the threshold.
        // Uploading only when needed avoids redundant generation on every key publication.
        // Without OPKs the strongest (4-DH) X3DH variant is unavailable for new sessions.
        let serverOPKCount = (try? await APIClient.shared.fetchOneTimePreKeyCount(token: token)) ?? 0
        if serverOPKCount < Self.opkReplenishThreshold {
            let otpks   = MessagingKeyStore.generateAndStoreOneTimePreKeys(count: Self.opkBatchSize)
            let payload = otpks.map { ["id": $0.id, "key": $0.publicKeyData.base64EncodedString()] }
            try await APIClient.shared.uploadOneTimePreKeys(keys: payload, token: token)
            Self.log.info("Replenished \(otpks.count) OPKs (server count was \(serverOPKCount))")
        } else {
            Self.log.info("OPK count sufficient (\(serverOPKCount)) — skipping replenishment")
        }
    }

    // MARK: - Encrypt (send path)

    /// Encrypts `plaintext` for the given contact.
    ///
    /// Returns `(wire, x3dhSenderKey, isFirst)`:
    /// - `wire` — base64 ciphertext to send as `encrypted_body`
    /// - `x3dhSenderKey` — non-nil on the first message only; the recipient uses it to
    ///   complete X3DH key agreement. Nil on subsequent messages (ratchet takes over).
    /// - `isFirst` — true if this establishes a new session.
    func encrypt(plaintext: String, forUserId contactUserId: Int,
                 bundle: UserKeyBundle) throws -> (wire: String, x3dhSenderKey: String?, isFirst: Bool) {
        let isFirst = !MessagingKeyStore.hasSession(for: contactUserId)
        let state: RatchetState

        if isFirst {
            let identity  = MessagingKeyStore.identityKey
            let preBundle = PreKeyBundle(
                userId:                bundle.userId,
                identityKey:           Data(base64Encoded: bundle.identityKey) ?? Data(),
                identitySigningKey:    bundle.identitySigningKey.flatMap { Data(base64Encoded: $0) },
                signedPreKey:          Data(base64Encoded: bundle.signedPreKey) ?? Data(),
                signedPreKeySignature: Data(base64Encoded: bundle.signedPreKeySignature) ?? Data(),
                oneTimePreKey:         bundle.oneTimePreKey.flatMap { Data(base64Encoded: $0) },
                oneTimePreKeyId:       bundle.oneTimePreKeyId
            )
            if preBundle.identitySigningKey == nil {
                if Self.requirePreKeyVerification {
                    // Strict mode: refuse to establish sessions that cannot be verified.
                    // Flip requirePreKeyVerification to true once server ships identitySigningKey.
                    throw FraiseMessagingError.unverifiablePreKey
                }
                Self.log.critical("Session for user \(contactUserId) established without prekey verification — identitySigningKey absent from server bundle")
            }
            let x3dh = try x3dhSend(senderIdentity: identity, recipientBundle: preBundle)
            state    = try initSendRatchet(
                masterSecret: x3dh.masterSecret,
                recipientPublicKey: preBundle.signedPreKey
            )
        } else {
            guard let existing = MessagingKeyStore.session(for: contactUserId) else {
                throw FraiseMessagingError.noSession
            }
            state = existing
        }

        let (newState, encrypted) = try ratchetEncrypt(state: state, plaintext: plaintext)
        MessagingKeyStore.save(newState, for: contactUserId)

        let senderKey = isFirst
            ? MessagingKeyStore.identityKey.publicKeyBytes.base64EncodedString()
            : nil

        return (encrypted.toWire(), senderKey, isFirst)
    }

    // MARK: - Decrypt (receive path)

    /// Decrypts a received `PlatformMessage` and returns the plaintext.
    /// Throws `FraiseMessagingError.decryptionFailed` if the session state cannot decrypt the message.
    /// Message keys are deleted after use — forward secrecy holds even if this call succeeds.
    func decrypt(message: PlatformMessage) throws -> String {
        if let cached = MessageCache.get(message.id) { return cached }

        guard let enc = EncryptedMessage.fromWire(message.encryptedBody) else {
            throw FraiseMessagingError.malformed
        }

        let senderId = message.senderId
        let state: RatchetState

        if let existing = MessagingKeyStore.session(for: senderId) {
            state = existing
        } else {
            // X3DH receive: reconstruct the shared secret from the sender's identity key.
            guard let senderKeyStr = message.x3dhSenderKey,
                  let senderIdentityKey = Data(base64Encoded: senderKeyStr) else {
                throw FraiseMessagingError.noSession
            }

            // TOFU: on first contact, record the sender's identity key.
            // On all subsequent X3DH receives, verify it hasn't changed.
            // A mismatch means reinstall (benign) or MitM substitution (malicious) —
            // both look identical here; only out-of-band verification can distinguish them.
            if let known = MessagingKeyStore.knownIdentityKey(for: senderId) {
                guard known == senderIdentityKey else {
                    Self.log.critical("Identity key changed for user \(senderId) — possible MitM or reinstall")
                    throw FraiseMessagingError.identityKeyChanged
                }
            } else {
                MessagingKeyStore.saveKnownIdentityKey(senderIdentityKey, for: senderId)
                Self.log.info("First-contact trust established for user \(senderId)")
            }

            let identity  = MessagingKeyStore.identityKey
            let signedPre = MessagingKeyStore.signedPreKey

            // Consume the one-time prekey if the sender used one (strongest X3DH variant).
            let otpk: MessagingKeyPair?
            if let otpkId = message.oneTimePreKeyId {
                otpk = MessagingKeyStore.consumeOneTimePreKey(id: otpkId)
            } else {
                otpk = nil
            }

            let masterSecret = try x3dhReceive(
                recipientIdentity:     identity,
                recipientSignedPreKey: signedPre,
                senderIdentityKey:     senderIdentityKey,
                senderEphemeralKey:    enc.ephemeralKey,
                recipientOneTimePreKey: otpk
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

    // Signs the signed prekey's DH public bytes with the identity signing key (Ed25519).
    // The recipient verifies this with the identity signing public key from the key bundle,
    // proving the identity key holder authorised this prekey for key agreement.
    private func signPreKey(_ preKey: MessagingKeyPair, with identity: MessagingKeyPair) throws -> String {
        let sig = try identity.signingKey.signature(for: preKey.publicKeyBytes)
        return Data(sig).base64EncodedString()
    }
}
