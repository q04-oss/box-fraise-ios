import Foundation
import Darwin
import UIKit
import CryptoKit

// MARK: - App security checks

enum AppSecurity {

    // MARK: - Jailbreak detection

    static func isJailbroken() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return hasJailbreakFiles()
            || canWriteOutsideSandbox()
            || hasSuspiciousURLSchemes()
            || hasDynamicLibraryInjection()
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
        return schemes.contains {
            UIApplication.shared.canOpenURL(URL(string: $0)!)
        }
    }

    private static func hasDynamicLibraryInjection() -> Bool {
        return ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil
    }

    // MARK: - Debugger detection

    static func isDebuggerAttached() -> Bool {
        #if DEBUG
        return false // Allow debugger in development
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

    /// Call on app launch. Terminates the app if running in a compromised environment.
    static func enforce() {
        if isDebuggerAttached() {
            exit(0)
        }
        if isJailbroken() {
            // Degrade silently rather than crash — crashing is more visible to attackers
            // In production you may want to show an alert and exit
            UserDefaults.standard.set(true, forKey: "fraise_compromised")
        }
    }

    static var isCompromised: Bool {
        UserDefaults.standard.bool(forKey: "fraise_compromised")
    }
}

// MARK: - Certificate pinning delegate

final class PinningDelegate: NSObject, URLSessionDelegate {
    // SHA-256 of the SubjectPublicKeyInfo (SPKI) for fraise.box
    // To get this value run:
    //   openssl s_client -connect fraise.box:443 | openssl x509 -pubkey -noout |
    //   openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
    private static let pinnedHashes: Set<String> = [
        "4ds9LCAvlHQB8boxWg9GOhXP4kY7D39TGVCMkbiPYu0=",
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

        // Standard trust evaluation first
        var secResult = SecTrustResultType.invalid
        SecTrustEvaluate(serverTrust, &secResult)
        guard secResult == .unspecified || secResult == .proceed else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract public key hash from the leaf certificate
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
            // Unknown key type — hash raw key bytes as fallback
            let digest = SHA256.hash(data: keyData)
            return Data(digest).base64EncodedString()
        }

        let spki = header + keyData
        let digest = SHA256.hash(data: spki)
        return Data(digest).base64EncodedString()
    }
}
