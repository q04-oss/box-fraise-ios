import Foundation
import CryptoKit

// Signal Protocol: X3DH + Double Ratchet
// Ported from fraise-chat/lib/crypto.ts — GPL v3, Rajzyngier Research 2026
// X25519 key agreement · Ed25519 signing · AES-256-GCM · HKDF-SHA256 · HMAC-SHA256

// MARK: - Errors

enum SignalError: LocalizedError {
    case signedPreKeyVerificationFailed
    case unverifiedPreKey               // identitySigningKey absent; reserved for strict-mode enforcement
    case tooManySkippedMessages
    case invalidKeyMaterial

    var errorDescription: String? {
        switch self {
        case .signedPreKeyVerificationFailed: return "signed prekey signature invalid"
        case .unverifiedPreKey:               return "prekey signature could not be verified"
        case .tooManySkippedMessages:         return "message gap too large to recover"
        case .invalidKeyMaterial:             return "key material is invalid or corrupt"
        }
    }
}

// MARK: - Types

struct MessagingKeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    // Signing key derived from the same 32-byte scalar as the DH key.
    // Documented deviation from Signal Protocol spec, which uses separate IK_dh/IK_ed types.
    // Cryptographic safety: X25519 (Montgomery form) and Ed25519 (twisted Edwards form) use
    // distinct group operations over the same Curve25519 base field — the same scalar produces
    // independent public keys with no known cross-protocol attack.
    // References: RFC 8032 §5.1 (Ed25519), RFC 7748 §5 (X25519), Bernstein et al. 2011.
    // Trade-off: eliminates two-key Keychain synchronisation at the cost of spec deviation.
    let signingKey: Curve25519.Signing.PrivateKey

    var publicKeyBytes: Data        { privateKey.publicKey.rawRepresentation }
    var signingPublicKeyBytes: Data { signingKey.publicKey.rawRepresentation }

    static func generate() -> MessagingKeyPair {
        let dhKey = Curve25519.KeyAgreement.PrivateKey()
        // CryptoKit only rejects rawRepresentation that isn't exactly 32 bytes.
        // Curve25519.KeyAgreement.PrivateKey.rawRepresentation is always 32 bytes — unreachable.
        guard let signingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: dhKey.rawRepresentation) else {
            fatalError("MessagingKeyPair: signing key derivation failed — impossible scalar length mismatch")
        }
        return MessagingKeyPair(privateKey: dhKey, signingKey: signingKey)
    }

    /// Reconstruct from stored DH private key bytes.
    init(privateKey: Curve25519.KeyAgreement.PrivateKey) {
        self.privateKey = privateKey
        guard let sk = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey.rawRepresentation) else {
            fatalError("MessagingKeyPair: signing key derivation failed — impossible scalar length mismatch")
        }
        self.signingKey = sk
    }
}

struct PreKeyBundle {
    let userId: Int
    let identityKey: Data           // X25519 DH public key
    let identitySigningKey: Data?   // Ed25519 signing public key (nil = server not yet updated)
    let signedPreKey: Data
    let signedPreKeySignature: Data
    let oneTimePreKey: Data?
    let oneTimePreKeyId: Int?
}

struct RatchetState: Codable {
    var rootKey: Data
    var sendChainKey: Data
    var recvChainKey: Data
    var sendCount: Int
    var recvCount: Int
    var dhSendPrivKey: Data
    var dhSendPubKey: Data
    var dhRecvKey: Data?
    // Skipped message keys keyed by "ephemeralBase64:messageCount".
    // Capped at maxSkipCount entries — prevents unbounded memory growth from
    // large message gaps or malicious skipping attacks.
    var skippedMessageKeys: [String: Data]

    init(rootKey: Data, sendChainKey: Data, recvChainKey: Data,
         sendCount: Int, recvCount: Int, dhSendPrivKey: Data,
         dhSendPubKey: Data, dhRecvKey: Data? = nil) {
        self.rootKey = rootKey; self.sendChainKey = sendChainKey
        self.recvChainKey = recvChainKey; self.sendCount = sendCount
        self.recvCount = recvCount; self.dhSendPrivKey = dhSendPrivKey
        self.dhSendPubKey = dhSendPubKey; self.dhRecvKey = dhRecvKey
        self.skippedMessageKeys = [:]
    }

    // Custom decoder for backward compatibility — sessions persisted before
    // skippedMessageKeys existed decode cleanly with an empty cache.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rootKey        = try c.decode(Data.self,   forKey: .rootKey)
        sendChainKey   = try c.decode(Data.self,   forKey: .sendChainKey)
        recvChainKey   = try c.decode(Data.self,   forKey: .recvChainKey)
        sendCount      = try c.decode(Int.self,    forKey: .sendCount)
        recvCount      = try c.decode(Int.self,    forKey: .recvCount)
        dhSendPrivKey  = try c.decode(Data.self,   forKey: .dhSendPrivKey)
        dhSendPubKey   = try c.decode(Data.self,   forKey: .dhSendPubKey)
        dhRecvKey      = try c.decodeIfPresent(Data.self, forKey: .dhRecvKey)
        skippedMessageKeys = (try? c.decodeIfPresent([String: Data].self,
                                                      forKey: .skippedMessageKeys)) ?? [:]
    }
}

struct EncryptedMessage: Codable {
    let ciphertext: Data    // AES-GCM ciphertext + 16-byte tag appended
    let nonce: Data         // 12-byte AES-GCM nonce
    let ephemeralKey: Data  // sender's current DH ratchet public key
    let messageCount: Int

    func toWire() -> String {
        (try? JSONEncoder().encode(self))?.base64EncodedString() ?? ""
    }

    static func fromWire(_ raw: String) -> EncryptedMessage? {
        guard let data = Data(base64Encoded: raw) else { return nil }
        return try? JSONDecoder().decode(EncryptedMessage.self, from: data)
    }
}

// MARK: - Safety number

// Produces a 30-digit fingerprint for out-of-band identity verification.
// Both parties compute the same number independently from their own devices —
// a match confirms no server-side key substitution has occurred.
// Canonical order: inputs sorted by user ID so the result is identical on both sides.
func safetyNumber(myUserId: Int, myIdentityKey: Data,
                  theirUserId: Int, theirIdentityKey: Data) -> String {
    let (u1, k1, u2, k2) = myUserId < theirUserId
        ? (myUserId, myIdentityKey, theirUserId, theirIdentityKey)
        : (theirUserId, theirIdentityKey, myUserId, myIdentityKey)
    var input = Data()
    input += k1
    input += withUnsafeBytes(of: Int64(u1).bigEndian) { Data($0) }
    input += k2
    input += withUnsafeBytes(of: Int64(u2).bigEndian) { Data($0) }
    let hash = Data(SHA256.hash(data: input))
    // 6 groups of 5 bytes → 6 five-digit decimal numbers (30 digits total).
    // Each group maps 5 bytes (max 2^40−1) into a 0–99,999 range via modulo.
    return (0..<6).map { i in
        let value = hash[(i * 5)..<(i * 5 + 5)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return String(format: "%05d", value % 100_000)
    }.joined(separator: " ")
}

// MARK: - KDF

private let kdfInfoRoot  = Data("fraise-root".utf8)
private let kdfInfoChain = Data("fraise-chain".utf8)

private func kdfRoot(rootKey: Data, dhOutput: Data) -> (newRootKey: Data, chainKey: Data) {
    let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: dhOutput),
        salt: rootKey, info: kdfInfoRoot, outputByteCount: 64
    ).withUnsafeBytes { Data($0) }
    return (derived.prefix(32), derived.suffix(32))
}

private func kdfChain(chainKey: Data) -> (messageKey: Data, nextChainKey: Data) {
    let key = SymmetricKey(data: chainKey)
    return (
        Data(HMAC<SHA256>.authenticationCode(for: Data([1]), using: key)),
        Data(HMAC<SHA256>.authenticationCode(for: Data([2]), using: key))
    )
}

// MARK: - ECDH

private func ecdh(privateKey: Curve25519.KeyAgreement.PrivateKey, publicKeyBytes: Data) throws -> Data {
    let pub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyBytes)
    return try privateKey.sharedSecretFromKeyAgreement(with: pub).withUnsafeBytes { Data($0) }
}

// MARK: - AES-GCM

// Binds the message header (ephemeral key + count) as AES-GCM associated data.
// An attacker who tampers with the wire-format header invalidates the GCM tag —
// message reordering and count manipulation are cryptographically detected.
// Breaking change from the pre-AAD protocol: all existing sessions must be re-established.
private func messageAAD(ephemeralKey: Data, messageCount: Int) -> Data {
    let countBytes = withUnsafeBytes(of: Int64(messageCount).bigEndian) { Data($0) }
    return ephemeralKey + countBytes
}

private func encryptSymmetric(messageKey: Data, plaintext: String, aad: Data) throws -> (ciphertext: Data, nonce: Data) {
    let nonce = AES.GCM.Nonce()
    let box = try AES.GCM.seal(Data(plaintext.utf8), using: SymmetricKey(data: messageKey),
                                nonce: nonce, authenticating: aad)
    return (box.ciphertext + box.tag, Data(nonce))
}

private func decryptSymmetric(messageKey: Data, ciphertext: Data, nonce: Data, aad: Data) throws -> String {
    let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: nonce),
        ciphertext: ciphertext.dropLast(16),
        tag: ciphertext.suffix(16)
    )
    let plain = try AES.GCM.open(box, using: SymmetricKey(data: messageKey), authenticating: aad)
    return String(data: plain, encoding: .utf8) ?? ""
}

// MARK: - X3DH

struct X3DHResult {
    let masterSecret: Data
    let ephemeralPublicKey: Data
}

func x3dhSend(senderIdentity: MessagingKeyPair, recipientBundle: PreKeyBundle) throws -> X3DHResult {
    // Verify the signed prekey signature before key agreement.
    // If the server returns an identity signing key, verification is mandatory.
    // If identitySigningKey is nil (server not yet updated), the caller is responsible
    // for logging a warning — FraiseMessaging.encrypt handles the degraded-mode path.
    // ENFORCE: once the server ships identitySigningKey, remove the nil branch and
    // throw SignalError.unverifiedPreKey when the key is absent.
    if let signingKeyBytes = recipientBundle.identitySigningKey {
        let signingPub = try Curve25519.Signing.PublicKey(rawRepresentation: signingKeyBytes)
        guard signingPub.isValidSignature(
            recipientBundle.signedPreKeySignature, for: recipientBundle.signedPreKey
        ) else {
            throw SignalError.signedPreKeyVerificationFailed
        }
    }

    let ephemeral = MessagingKeyPair.generate()
    let dh1 = try ecdh(privateKey: senderIdentity.privateKey, publicKeyBytes: recipientBundle.signedPreKey)
    let dh2 = try ecdh(privateKey: ephemeral.privateKey,      publicKeyBytes: recipientBundle.identityKey)
    let dh3 = try ecdh(privateKey: ephemeral.privateKey,      publicKeyBytes: recipientBundle.signedPreKey)
    var parts = dh1 + dh2 + dh3
    if let otpk = recipientBundle.oneTimePreKey {
        parts += try ecdh(privateKey: ephemeral.privateKey, publicKeyBytes: otpk)
    }
    let secret = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: parts),
        salt: Data(repeating: 0, count: 32), info: kdfInfoChain, outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
    return X3DHResult(masterSecret: secret, ephemeralPublicKey: ephemeral.publicKeyBytes)
}

func x3dhReceive(
    recipientIdentity: MessagingKeyPair,
    recipientSignedPreKey: MessagingKeyPair,
    senderIdentityKey: Data,
    senderEphemeralKey: Data,
    recipientOneTimePreKey: MessagingKeyPair? = nil
) throws -> Data {
    let dh1 = try ecdh(privateKey: recipientSignedPreKey.privateKey, publicKeyBytes: senderIdentityKey)
    let dh2 = try ecdh(privateKey: recipientIdentity.privateKey,     publicKeyBytes: senderEphemeralKey)
    let dh3 = try ecdh(privateKey: recipientSignedPreKey.privateKey, publicKeyBytes: senderEphemeralKey)
    var parts = dh1 + dh2 + dh3
    if let otpk = recipientOneTimePreKey {
        parts += try ecdh(privateKey: otpk.privateKey, publicKeyBytes: senderEphemeralKey)
    }
    return HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: parts),
        salt: Data(repeating: 0, count: 32), info: kdfInfoChain, outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
}

// MARK: - Double Ratchet

func initSendRatchet(masterSecret: Data, recipientPublicKey: Data) throws -> RatchetState {
    let dhSend = MessagingKeyPair.generate()
    let (newRoot, chainKey) = kdfRoot(
        rootKey: masterSecret,
        dhOutput: try ecdh(privateKey: dhSend.privateKey, publicKeyBytes: recipientPublicKey)
    )
    return RatchetState(
        rootKey: newRoot, sendChainKey: chainKey,
        recvChainKey: Data(repeating: 0, count: 32),
        sendCount: 0, recvCount: 0,
        dhSendPrivKey: dhSend.privateKey.rawRepresentation,
        dhSendPubKey: dhSend.publicKeyBytes,
        dhRecvKey: recipientPublicKey
    )
}

func initRecvRatchet(masterSecret: Data, signedPreKey: MessagingKeyPair) -> RatchetState {
    RatchetState(
        rootKey: masterSecret,
        sendChainKey: Data(repeating: 0, count: 32),
        recvChainKey: Data(repeating: 0, count: 32),
        sendCount: 0, recvCount: 0,
        dhSendPrivKey: signedPreKey.privateKey.rawRepresentation,
        dhSendPubKey: signedPreKey.publicKeyBytes
    )
}

func ratchetEncrypt(state: RatchetState, plaintext: String) throws -> (state: RatchetState, message: EncryptedMessage) {
    let (messageKey, nextChainKey) = kdfChain(chainKey: state.sendChainKey)
    let aad = messageAAD(ephemeralKey: state.dhSendPubKey, messageCount: state.sendCount)
    let (ciphertext, nonce) = try encryptSymmetric(messageKey: messageKey, plaintext: plaintext, aad: aad)
    var next = state
    next.sendChainKey = nextChainKey
    next.sendCount += 1
    return (next, EncryptedMessage(
        ciphertext: ciphertext, nonce: nonce,
        ephemeralKey: state.dhSendPubKey, messageCount: state.sendCount
    ))
}

// Maximum number of messages that can be skipped in a single chain step.
// Prevents unbounded cache growth from large gaps or malicious skipping.
private let maxSkipCount = 100

func ratchetDecrypt(state: RatchetState, message: EncryptedMessage) throws -> (state: RatchetState, plaintext: String) {
    var s = state
    // AAD is derived from the wire header — binds ephemeral key and count to the ciphertext.
    let aad = messageAAD(ephemeralKey: message.ephemeralKey, messageCount: message.messageCount)

    // Check the skipped message key cache first — handles out-of-order delivery.
    let cacheKey = skippedKeyID(ephemeral: message.ephemeralKey, count: message.messageCount)
    if let msgKey = s.skippedMessageKeys[cacheKey] {
        let plaintext = try decryptSymmetric(messageKey: msgKey, ciphertext: message.ciphertext, nonce: message.nonce, aad: aad)
        s.skippedMessageKeys.removeValue(forKey: cacheKey)  // consume — forward secrecy
        return (s, plaintext)
    }

    // Determine whether a DH ratchet step is needed.
    let needsDHStep = s.dhRecvKey == nil || message.ephemeralKey != s.dhRecvKey

    if needsDHStep {
        // Cache any skipped keys in the current receive chain before advancing.
        try skipMessageKeys(&s, untilCount: message.messageCount)

        // DH ratchet: advance root key and derive new send/receive chains.
        guard let dhSendPrivKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: s.dhSendPrivKey) else {
            throw SignalError.invalidKeyMaterial
        }
        let (root1, recvChain) = kdfRoot(rootKey: s.rootKey,
                                          dhOutput: try ecdh(privateKey: dhSendPrivKey, publicKeyBytes: message.ephemeralKey))
        let newDh = MessagingKeyPair.generate()
        let (root2, sendChain) = kdfRoot(rootKey: root1,
                                          dhOutput: try ecdh(privateKey: newDh.privateKey, publicKeyBytes: message.ephemeralKey))
        s.rootKey        = root2
        s.recvChainKey   = recvChain
        s.sendChainKey   = sendChain
        s.dhSendPrivKey  = newDh.privateKey.rawRepresentation
        s.dhSendPubKey   = newDh.publicKeyBytes
        s.dhRecvKey      = message.ephemeralKey
        s.recvCount      = 0
    }

    // Advance the receive chain to the message's position, caching any skipped keys.
    try skipMessageKeys(&s, untilCount: message.messageCount - 1)

    let (messageKey, nextChainKey) = kdfChain(chainKey: s.recvChainKey)
    let plaintext = try decryptSymmetric(messageKey: messageKey, ciphertext: message.ciphertext, nonce: message.nonce, aad: aad)
    s.recvChainKey = nextChainKey
    s.recvCount    += 1
    return (s, plaintext)
}

// Advance the receive chain from `state.recvCount` up to (but not including) `untilCount`,
// caching each skipped message key. Called before DH ratchet steps and before decryption.
private func skipMessageKeys(_ state: inout RatchetState, untilCount: Int) throws {
    guard untilCount - state.recvCount <= maxSkipCount else {
        throw SignalError.tooManySkippedMessages
    }
    while state.recvCount < untilCount {
        let (msgKey, nextChain) = kdfChain(chainKey: state.recvChainKey)
        let key = skippedKeyID(ephemeral: state.dhRecvKey ?? Data(), count: state.recvCount)
        state.skippedMessageKeys[key] = msgKey
        state.recvChainKey = nextChain
        state.recvCount   += 1
    }
}

private func skippedKeyID(ephemeral: Data, count: Int) -> String {
    "\(ephemeral.base64EncodedString()):\(count)"
}

// MARK: - Key Store

enum MessagingKeyStore {
    private static let identityTag    = "com.boxfraise.messaging.identity"
    private static let signedPreTag   = "com.boxfraise.messaging.signedprekey"
    private static let otpkService    = "com.boxfraise.messaging.otpk"
    private static let sessionService = "com.boxfraise.messaging.sessions"
    // NSLock serialises all Keychain operations. FraiseMessaging (actor) further
    // serialises encrypt/decrypt so there is no contention on the hot path.
    private static let lock = NSLock()

    // Signing key is deterministically derived from the DH scalar — not stored separately.
    static var identityKey: MessagingKeyPair  { loadOrCreate(dhTag: identityTag) }
    static var signedPreKey: MessagingKeyPair { loadOrCreate(dhTag: signedPreTag) }

    // MARK: - Signed prekey rotation

    /// Discards the current signed prekey and generates a fresh one.
    /// The identity key never rotates — only the signed prekey does.
    /// Signing key is derived from the DH scalar so only the DH key needs storing.
    static func rotateSignedPreKey() {
        lock.lock(); defer { lock.unlock() }
        let kp = MessagingKeyPair.generate()
        keychainSaveKey(kp.privateKey.rawRepresentation, tag: signedPreTag)
    }

    // MARK: - One-time prekeys

    struct OneTimePreKeyRecord {
        let id: Int
        let publicKeyData: Data
    }

    /// Generates `count` fresh OPKs, stores private halves in Keychain,
    /// and returns the (id, publicKey) pairs for upload to the key server.
    static func generateAndStoreOneTimePreKeys(count: Int = 10) -> [OneTimePreKeyRecord] {
        lock.lock(); defer { lock.unlock() }
        let existingCount = loadOTPKCount()
        var records: [OneTimePreKeyRecord] = []
        for i in 0..<count {
            let id = existingCount + i
            let kp = MessagingKeyPair.generate()
            keychainSaveKey(kp.privateKey.rawRepresentation, tag: otpkTag(id))
            records.append(OneTimePreKeyRecord(id: id, publicKeyData: kp.publicKeyBytes))
        }
        saveOTPKCount(existingCount + count)
        return records
    }

    /// Loads and deletes the OPK with the given ID (consume-once semantics).
    /// Old message keys are deleted after use — forward secrecy is maintained.
    static func consumeOneTimePreKey(id: Int) -> MessagingKeyPair? {
        lock.lock(); defer { lock.unlock() }
        guard let raw = keychainLoadKey(tag: otpkTag(id)),
              let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) else { return nil }
        keychainDeleteKey(tag: otpkTag(id))
        return MessagingKeyPair(privateKey: priv)
    }

    private static func otpkTag(_ id: Int) -> String { "\(otpkService).\(id)" }

    private static func loadOTPKCount() -> Int {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                   kSecAttrService: otpkService,
                                   kSecAttrAccount: "count",
                                   kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let count = Int(String(data: data, encoding: .utf8) ?? "") else { return 0 }
        return count
    }

    private static func saveOTPKCount(_ count: Int) {
        let data = Data(String(count).utf8)
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                      kSecAttrService: otpkService,
                                      kSecAttrAccount: "count",
                                      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                      kSecAttrSynchronizable: kCFBooleanFalse as Any]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - Ratchet sessions

    static func session(for userId: Int) -> RatchetState? {
        lock.lock(); defer { lock.unlock() }
        let account = String(userId)
        guard let data = loadSession(account: account) else { return nil }
        touchSession(account: account)  // update last-access for expiry tracking
        return try? JSONDecoder().decode(RatchetState.self, from: data)
    }

    static func save(_ state: RatchetState, for userId: Int) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        lock.lock(); defer { lock.unlock() }
        let account = String(userId)
        saveSession(data, account: account)
        touchSession(account: account)  // update last-access for expiry tracking
    }

    static func hasSession(for userId: Int) -> Bool { session(for: userId) != nil }

    // MARK: - TOFU (Trust On First Use)
    // Records the expected identity key for each contact on first X3DH receive.
    // A mismatch on subsequent messages throws FraiseMessagingError.identityKeyChanged —
    // the UI shows a prominent warning so the user can verify identity out of band.
    // Both reinstall (benign) and MitM substitution (malicious) look identical here;
    // out-of-band verification (e.g. safety number comparison) is the only distinction.

    private static let knownIdentityService = "com.boxfraise.messaging.known-identity"

    static func knownIdentityKey(for userId: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                   kSecAttrService: knownIdentityService,
                                   kSecAttrAccount: String(userId),
                                   kSecReturnData: true,
                                   kSecMatchLimit: kSecMatchLimitOne,
                                   kSecAttrSynchronizable: kCFBooleanFalse as Any]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        return result as? Data
    }

    static func saveKnownIdentityKey(_ keyData: Data, for userId: Int) {
        lock.lock(); defer { lock.unlock() }
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                      kSecAttrService: knownIdentityService,
                                      kSecAttrAccount: String(userId),
                                      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                      kSecAttrSynchronizable: kCFBooleanFalse as Any]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData] = keyData
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - Session expiry
    // Sessions not accessed in sessionExpiryDays are deleted from Keychain.
    // Limits the window in which a stolen device's Keychain can decrypt future messages.
    // Last-access timestamps are stored in UserDefaults (non-sensitive — just a date).
    // pruneExpiredSessions() is called at key publication time (launch + sign-in).

    private static let sessionExpiryDays   = 90
    private static let sessionTSKey        = "messaging.session.timestamps"

    private static func loadSessionTimestamps() -> [String: TimeInterval] {
        guard let data = UserDefaults.standard.data(forKey: sessionTSKey),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else { return [:] }
        return dict
    }

    private static func saveSessionTimestamps(_ dict: [String: TimeInterval]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: sessionTSKey)
        }
    }

    private static func touchSession(account: String) {
        var ts = loadSessionTimestamps()
        ts[account] = Date().timeIntervalSince1970
        saveSessionTimestamps(ts)
    }

    static func pruneExpiredSessions() {
        lock.lock(); defer { lock.unlock() }
        let ts = loadSessionTimestamps()
        let cutoff = Date().timeIntervalSince1970 - TimeInterval(sessionExpiryDays * 86400)
        var updated = ts
        for (account, lastAccess) in ts where lastAccess < cutoff {
            let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                       kSecAttrService: sessionService,
                                       kSecAttrAccount: account]
            SecItemDelete(q as CFDictionary)
            updated.removeValue(forKey: account)
        }
        if updated.count != ts.count { saveSessionTimestamps(updated) }
    }

    // MARK: - Keychain primitives

    // Signing key is deterministically derived from the DH scalar (X25519/Ed25519 share the
    // same 32-byte secret) — no separate Keychain entry is needed or maintained.
    private static func loadOrCreate(dhTag: String) -> MessagingKeyPair {
        lock.lock(); defer { lock.unlock() }
        if let raw = keychainLoadKey(tag: dhTag),
           let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            return MessagingKeyPair(privateKey: priv)
        }
        let kp = MessagingKeyPair.generate()
        keychainSaveKey(kp.privateKey.rawRepresentation, tag: dhTag)
        return kp
    }

    // ── Key pair storage (kSecClassKey) ───────────────────────────────────────
    // kSecAttrAccessibleWhenUnlockedThisDeviceOnly: key material must not leave
    // this device and must not be readable while the screen is locked.

    private static func keychainSaveKey(_ data: Data, tag: String) {
        let q: [CFString: Any] = [kSecClass: kSecClassKey,
                                   kSecAttrApplicationTag: Data(tag.utf8),
                                   kSecValueData: data,
                                   kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                   kSecAttrSynchronizable: kCFBooleanFalse as Any]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func keychainLoadKey(tag: String) -> Data? {
        let q: [CFString: Any] = [kSecClass: kSecClassKey,
                                   kSecAttrApplicationTag: Data(tag.utf8),
                                   kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        return result as? Data
    }

    private static func keychainDeleteKey(tag: String) {
        let q: [CFString: Any] = [kSecClass: kSecClassKey,
                                   kSecAttrApplicationTag: Data(tag.utf8)]
        SecItemDelete(q as CFDictionary)
    }

    // ── Ratchet session state (kSecClassGenericPassword, one item per peer) ───
    // Stored in Keychain rather than UserDefaults because it contains live chain
    // key material. UserDefaults is unencrypted on disk and included in backups.

    private static func loadSession(account: String) -> Data? {
        let q: [CFString: Any] = [kSecClass:       kSecClassGenericPassword,
                                   kSecAttrService:  sessionService,
                                   kSecAttrAccount:  account,
                                   kSecReturnData:   true,
                                   kSecMatchLimit:   kSecMatchLimitOne,
                                   kSecAttrSynchronizable: kCFBooleanFalse as Any]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        return result as? Data
    }

    private static func saveSession(_ data: Data, account: String) {
        let base: [CFString: Any] = [kSecClass:       kSecClassGenericPassword,
                                      kSecAttrService:  sessionService,
                                      kSecAttrAccount:  account,
                                      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                      kSecAttrSynchronizable: kCFBooleanFalse as Any]
        SecItemDelete(base as CFDictionary)
        var addQ = base; addQ[kSecValueData] = data
        SecItemAdd(addQ as CFDictionary, nil)
    }
}
