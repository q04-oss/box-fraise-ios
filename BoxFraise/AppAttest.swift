import Foundation
import DeviceCheck
import CryptoKit
import os.log

// MARK: - App Attest + Secure Enclave
//
// Apple App Attest (SE-0293 / DeviceCheck framework):
//   1. The Secure Enclave generates an asymmetric key pair — the private key never leaves the device.
//   2. Apple signs the public key with their App Attest CA, binding it to this app's App ID and
//      a server-provided challenge. This proves the binary is unmodified on genuine Apple hardware.
//   3. For each API request, DCAppAttestService generates an ECDSA assertion over the request hash
//      using the attested private key. The server verifies the assertion with the stored public key.
//
// During attestation, the device also registers its per-device HMAC signing key with the server.
// The server can then validate HMAC signatures for this specific device independently of App Attest,
// providing defence-in-depth for requests from attested devices and the sole integrity layer
// for devices where App Attest is unavailable (simulator, iOS < 14).
//
// This layers on top of HMAC request signing — both must pass for sensitive endpoints.
// If attestation is unavailable (simulator, old devices), HMAC signing continues as the sole layer.

@MainActor
final class AppAttest {
    static let shared = AppAttest()
    private init() {}

    private static let log = Logger(subsystem: "com.boxfraise.app", category: "security.attest")

    private let keyIDKey    = "fraise_attest_key_id"
    private let attestedKey = "fraise_attest_done"

    // False on simulator, Mac Catalyst, and devices below iOS 14. HMAC signing continues as the sole layer.
    var isSupported: Bool { DCAppAttestService.shared.isSupported }
    var keyID: String?    { Keychain.readMetadata(key: keyIDKey) }
    var isAttested: Bool  { Keychain.readMetadata(key: attestedKey) == "1" }

    /// Call once after sign-in. No-op if already attested or running in simulator.
    /// Also registers the device's HMAC signing key so the server can validate per-device signatures.
    func ensureAttestation(userToken: FraiseToken?) async {
        guard isSupported, !isAttested else {
            Self.log.debug("Attestation skipped — supported: \(self.isSupported), attested: \(self.isAttested)")
            return
        }
        do {
            let kid = try await getOrCreateKeyID()
            // Use a server-issued challenge so the server can verify the attestation was bound
            // to a challenge it generated — prevents replay of old attestation objects.
            let challenge = (try? await APIClient.shared.fetchAttestChallenge()) ?? Data(UUID().uuidString.utf8)
            let attestation = try await DCAppAttestService.shared.attestKey(
                kid, clientDataHash: Data(SHA256.hash(data: challenge))
            )
            // Retrieve the device HMAC key so the server can learn it during attestation.
            let hmacKeyData = await APIClient.shared.deviceSigningKeyData
            try await APIClient.shared.registerAttestation(
                keyID:      kid,
                attestation: attestation,
                challenge:   challenge,
                hmacKey:     hmacKeyData.base64EncodedString(),
                userToken:   userToken
            )
            Keychain.saveMetadata(key: attestedKey, value: "1")
            Self.log.info("App Attest registration succeeded — keyID: \(kid.prefix(8))…")
        } catch {
            // Non-fatal — HMAC signing continues as the request integrity layer.
            Self.log.error("App Attest registration failed: \(error.localizedDescription)")
        }
    }

    /// Generate a per-request assertion. Returns nil on simulator or unattested devices.
    func assertion(for requestData: Data) async -> String? {
        guard isSupported, let kid = keyID else { return nil }
        let assertion = try? await DCAppAttestService.shared.generateAssertion(
            kid, clientDataHash: Data(SHA256.hash(data: requestData))
        )
        return assertion?.base64EncodedString()
    }

    private func getOrCreateKeyID() async throws -> String {
        if let kid = Keychain.readMetadata(key: keyIDKey) { return kid }
        let kid = try await DCAppAttestService.shared.generateKey()
        Keychain.saveMetadata(key: keyIDKey, value: kid)
        Self.log.info("New App Attest key generated")
        return kid
    }
}
