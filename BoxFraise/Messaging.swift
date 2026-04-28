import Foundation
import CryptoKit

// Signal Protocol: X3DH + Double Ratchet
// Ported from fraise-chat/lib/crypto.ts — GPL v3, Rajzyngier Research 2026
// X25519 key agreement · AES-256-GCM · HKDF-SHA256 · HMAC-SHA256

// MARK: - Types

struct MessagingKeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    var publicKeyBytes: Data { privateKey.publicKey.rawRepresentation }

    static func generate() -> MessagingKeyPair {
        MessagingKeyPair(privateKey: .init())
    }
}

struct PreKeyBundle {
    let userId: Int
    let identityKey: Data
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

// MARK: - KDF

private let kdfInfoRoot    = Data("fraise-root".utf8)
private let kdfInfoChain   = Data("fraise-chain".utf8)

private func kdfRoot(rootKey: Data, dhOutput: Data) -> (newRootKey: Data, chainKey: Data) {
    let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: dhOutput),
        salt: rootKey,
        info: kdfInfoRoot,
        outputByteCount: 64
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

private func encryptSymmetric(messageKey: Data, plaintext: String) throws -> (ciphertext: Data, nonce: Data) {
    let nonce = AES.GCM.Nonce()
    let box = try AES.GCM.seal(Data(plaintext.utf8), using: SymmetricKey(data: messageKey), nonce: nonce)
    return (box.ciphertext + box.tag, Data(nonce))
}

private func decryptSymmetric(messageKey: Data, ciphertext: Data, nonce: Data) throws -> String {
    let box = try AES.GCM.SealedBox(
        nonce: AES.GCM.Nonce(data: nonce),
        ciphertext: ciphertext.dropLast(16),
        tag: ciphertext.suffix(16)
    )
    let plain = try AES.GCM.open(box, using: SymmetricKey(data: messageKey))
    return String(data: plain, encoding: .utf8) ?? ""
}

// MARK: - X3DH

struct X3DHResult {
    let masterSecret: Data
    let ephemeralPublicKey: Data
}

func x3dhSend(senderIdentity: MessagingKeyPair, recipientBundle: PreKeyBundle) throws -> X3DHResult {
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
        salt: Data(repeating: 0, count: 32),
        info: kdfInfoChain,
        outputByteCount: 32
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
        salt: Data(repeating: 0, count: 32),
        info: kdfInfoChain,
        outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
}

// MARK: - Double Ratchet

func initSendRatchet(masterSecret: Data, recipientPublicKey: Data) throws -> RatchetState {
    let dhSend = MessagingKeyPair.generate()
    let (newRoot, chainKey) = kdfRoot(rootKey: masterSecret, dhOutput: try ecdh(privateKey: dhSend.privateKey, publicKeyBytes: recipientPublicKey))
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
        dhSendPubKey: signedPreKey.publicKeyBytes,
        dhRecvKey: nil
    )
}

func ratchetEncrypt(state: RatchetState, plaintext: String) throws -> (state: RatchetState, message: EncryptedMessage) {
    let (messageKey, nextChainKey) = kdfChain(chainKey: state.sendChainKey)
    let (ciphertext, nonce) = try encryptSymmetric(messageKey: messageKey, plaintext: plaintext)
    var next = state
    next.sendChainKey = nextChainKey
    next.sendCount += 1
    return (next, EncryptedMessage(ciphertext: ciphertext, nonce: nonce, ephemeralKey: state.dhSendPubKey, messageCount: state.sendCount))
}

func ratchetDecrypt(state: RatchetState, message: EncryptedMessage) throws -> (state: RatchetState, plaintext: String) {
    var s = state

    if s.dhRecvKey == nil || message.ephemeralKey != s.dhRecvKey! {
        let sendPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: s.dhSendPrivKey)
        let (root1, recvChain) = kdfRoot(rootKey: s.rootKey, dhOutput: try ecdh(privateKey: sendPriv, publicKeyBytes: message.ephemeralKey))
        let newDh = MessagingKeyPair.generate()
        let (root2, sendChain) = kdfRoot(rootKey: root1, dhOutput: try ecdh(privateKey: newDh.privateKey, publicKeyBytes: message.ephemeralKey))
        s.rootKey = root2; s.recvChainKey = recvChain; s.sendChainKey = sendChain
        s.dhSendPrivKey = newDh.privateKey.rawRepresentation; s.dhSendPubKey = newDh.publicKeyBytes
        s.dhRecvKey = message.ephemeralKey; s.recvCount = 0
    }

    let (messageKey, nextChainKey) = kdfChain(chainKey: s.recvChainKey)
    let plaintext = try decryptSymmetric(messageKey: messageKey, ciphertext: message.ciphertext, nonce: message.nonce)
    s.recvChainKey = nextChainKey; s.recvCount += 1
    return (s, plaintext)
}

// MARK: - Key Store

enum MessagingKeyStore {
    private static let identityTag   = "com.boxfraise.messaging.identity"
    private static let signedPreTag  = "com.boxfraise.messaging.signedprekey"
    private static let sessionsKey   = "fraise_messaging_sessions"

    static var identityKey: MessagingKeyPair   { loadOrCreate(tag: identityTag) }
    static var signedPreKey: MessagingKeyPair  { loadOrCreate(tag: signedPreTag) }

    static func session(for userId: Int) -> RatchetState? {
        guard let dict = UserDefaults.standard.dictionary(forKey: sessionsKey),
              let data = dict[String(userId)] as? Data else { return nil }
        return try? JSONDecoder().decode(RatchetState.self, from: data)
    }

    static func save(_ state: RatchetState, for userId: Int) {
        var dict = UserDefaults.standard.dictionary(forKey: sessionsKey) ?? [:]
        dict[String(userId)] = try? JSONEncoder().encode(state)
        UserDefaults.standard.set(dict, forKey: sessionsKey)
    }

    static func hasSession(for userId: Int) -> Bool { session(for: userId) != nil }

    private static func loadOrCreate(tag: String) -> MessagingKeyPair {
        if let raw = keychainLoad(tag: tag),
           let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw) {
            return MessagingKeyPair(privateKey: priv)
        }
        let kp = MessagingKeyPair.generate()
        keychainSave(kp.privateKey.rawRepresentation, tag: tag)
        return kp
    }

    private static func keychainSave(_ data: Data, tag: String) {
        let q: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8),
                                   kSecValueData: data, kSecAttrSynchronizable: kCFBooleanFalse as Any]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func keychainLoad(tag: String) -> Data? {
        let q: [CFString: Any] = [kSecClass: kSecClassKey, kSecAttrApplicationTag: Data(tag.utf8),
                                   kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        return result as? Data
    }
}
