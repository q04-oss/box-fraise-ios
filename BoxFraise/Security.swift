import Foundation
import Darwin
import UIKit
import CryptoKit

// MARK: - App security checks

enum AppSecurity {

    // MARK: - Jailbreak detection

    // Cached in-process. A static stored in memory can't be cleared by an attacker
    // the way a UserDefaults flag can. Resets to nil on next app launch, re-running
    // the checks — which is desirable (device state may have changed).
    private static var _jailbreakCached: Bool?

    static func isJailbroken() -> Bool {
        if let cached = _jailbreakCached { return cached }
        #if targetEnvironment(simulator)
        _jailbreakCached = false
        return false
        #else
        let result = hasJailbreakFiles()
            || canWriteOutsideSandbox()
            || hasSuspiciousURLSchemes()
            || hasDynamicLibraryInjection()
        _jailbreakCached = result
        return result
        #endif
    }

    private static func hasJailbreakFiles() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
            "/private/var/lib/apt",
            "/usr/bin/ssh",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private static func hasSuspiciousURLSchemes() -> Bool {
        let schemes = ["cydia://", "sileo://", "zbra://", "filza://"]
        return schemes.compactMap { URL(string: $0) }.contains {
            UIApplication.shared.canOpenURL($0)
        }
    }

    private static func hasDynamicLibraryInjection() -> Bool {
        return ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil
    }

    // MARK: - Debugger detection

    static func isDebuggerAttached() -> Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    // MARK: - Enforcement

    static func enforce() {
        if isDebuggerAttached() { exit(0) }
        _ = isJailbroken() // warm the in-process cache at launch
        // Intentionally NOT persisting to UserDefaults: a stored flag can be
        // cleared by an attacker with device access. isCompromised re-evaluates
        // against the in-process cache instead.
    }

    static var isCompromised: Bool { isJailbroken() }
}

// MARK: - Certificate pinning delegate

final class PinningDelegate: NSObject, URLSessionDelegate {
    // SHA-256 of the SubjectPublicKeyInfo (SPKI) for fraise.box.
    // To regenerate after a cert rotation:
    //   openssl s_client -connect fraise.box:443 </dev/null | \
    //   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | \
    //   openssl dgst -sha256 -binary | base64
    //
    // Keep TWO hashes: current cert + the next one (add before the rotation,
    // remove the old one after). Let's Encrypt renews every ~60 days so
    // a release with the backup hash needs to ship before the renewal fires.
    private static let pinnedHashes: Set<String> = [
        "4ds9LCAvlHQB8boxWg9GOhXP4kY7D39TGVCMkbiPYu0=",   // current
        // "REPLACE_WITH_NEXT_CERT_SPKI_HASH=",            // add before next renewal
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Use non-deprecated SecTrustEvaluateWithError (replaces SecTrustEvaluate)
        var evalError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &evalError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let leafCert = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let publicKey = SecCertificateCopyKey(leafCert),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let hash = spkiHash(for: publicKey, keyData: publicKeyData)

        if Self.pinnedHashes.contains(hash) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func spkiHash(for key: SecKey, keyData: Data) -> String {
        let attrs = SecKeyCopyAttributes(key) as? [CFString: Any]
        let keyType = attrs?[kSecAttrKeyType] as? String ?? ""
        let keySize = attrs?[kSecAttrKeySizeInBits] as? Int ?? 0

        let header: Data
        if keyType == (kSecAttrKeyTypeRSA as String) && keySize == 2048 {
            header = Data([0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
                           0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                           0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00])
        } else if keyType == (kSecAttrKeyTypeRSA as String) && keySize == 4096 {
            header = Data([0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
                           0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                           0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00])
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) && keySize == 256 {
            header = Data([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
                           0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
                           0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                           0x42, 0x00])
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) && keySize == 384 {
            header = Data([0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
                           0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
                           0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00])
        } else {
            let digest = SHA256.hash(data: keyData)
            return Data(digest).base64EncodedString()
        }

        let spki = header + keyData
        let digest = SHA256.hash(data: spki)
        return Data(digest).base64EncodedString()
    }
}
