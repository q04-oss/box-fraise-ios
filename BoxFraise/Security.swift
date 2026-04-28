import Foundation
import Darwin
import Darwin.sys.ptrace
import MachO
import UIKit
import CryptoKit
import os

// MARK: - App security checks

enum AppSecurity {

    // MARK: - Jailbreak detection

    // OSAllocatedUnfairLock serialises the write-once cache without a dedicated queue.
    // State is Bool? — nil means unchecked, non-nil is the cached result.
    private static let _jailbreakLock = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    static func isJailbroken() -> Bool {
        _jailbreakLock.withLock { cached -> Bool in
            if let v = cached { return v }
            #if targetEnvironment(simulator)
            cached = false
            return false
            #else
            let result = hasJailbreakFiles()
                || canWriteOutsideSandbox()
                || hasSuspiciousURLSchemes()
                || hasDynamicLibraryInjection()
                || hasInjectedDylibs()
                || hasFridaServer()
            cached = result
            return result
            #endif
        }
    }

    private static func hasJailbreakFiles() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash", "/usr/sbin/sshd", "/etc/apt",
            "/private/var/lib/apt", "/usr/bin/ssh",
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func canWriteOutsideSandbox() -> Bool {
        let path = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch { return false }
    }

    private static func hasSuspiciousURLSchemes() -> Bool {
        let schemes = ["cydia://", "sileo://", "zbra://", "filza://"]
        return schemes.compactMap { URL(string: $0) }.contains {
            UIApplication.shared.canOpenURL($0)
        }
    }

    // Check DYLD_INSERT_LIBRARIES, DYLD_LIBRARY_PATH, DYLD_FRAMEWORK_PATH —
    // all three are standard injection vectors used by dynamic analysis tools.
    private static func hasDynamicLibraryInjection() -> Bool {
        let env = ProcessInfo.processInfo.environment
        return env["DYLD_INSERT_LIBRARIES"] != nil
            || env["DYLD_LIBRARY_PATH"]     != nil
            || env["DYLD_FRAMEWORK_PATH"]   != nil
    }

    // Walk the loaded image list for known dynamic analysis / hooking dylibs.
    // Frida injects FridaGadget.dylib; Substrate injects MobileSubstrate.dylib;
    // cycript injects libcycript.dylib. Any of these in-process = compromised.
    private static func hasInjectedDylibs() -> Bool {
        let suspicious = ["frida", "cynject", "cycript", "substrate", "substitute",
                          "libhooker", "fishhook", "inyectme"]
        let count = _dyld_image_count()
        for i in 0..<count {
            guard let raw = _dyld_get_image_name(i) else { continue }
            let name = String(cString: raw).lowercased()
            if suspicious.contains(where: { name.contains($0) }) { return true }
        }
        return false
    }

    // Frida server listens on localhost:27042 by default.
    // A successful TCP connect means a live Frida server is present.
    private static func hasFridaServer() -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        // Set non-blocking + short timeout so this doesn't stall the launch path
        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = UInt16(27042).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    // MARK: - Debugger detection + denial

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

    // Ask the kernel to refuse future debugger attaches for this process.
    // Complements the detection check: detection tells us if one is already
    // present; denial blocks one from being attached after launch.
    private static func denyDebuggerAttach() {
        #if !DEBUG
        ptrace(PT_DENY_ATTACH, 0, nil, 0)
        #endif
    }

    // MARK: - Enforcement

    static func enforce() {
        // Block the app from running in a simulator in release builds.
        // Simulator = no Secure Enclave, no App Attest, trivially reversible.
        #if !DEBUG && targetEnvironment(simulator)
        exit(0)
        #endif
        denyDebuggerAttach()
        if isDebuggerAttached() { exit(0) }
        // Fast checks (file paths, sandbox write, URL schemes, dylibs) run inline.
        // hasFridaServer() opens a socket with a 300 ms timeout — runs on a background
        // thread so it never stalls the launch path. The lock ensures only one winner.
        #if !targetEnvironment(simulator)
        if hasJailbreakFiles() || canWriteOutsideSandbox()
            || hasSuspiciousURLSchemes() || hasDynamicLibraryInjection()
            || hasInjectedDylibs() {
            exit(0)
        }
        Task.detached(priority: .background) {
            if hasFridaServer() { exit(0) }
        }
        #endif
    }

    // Re-evaluates against the in-process cache. Never reads from UserDefaults —
    // a persisted flag can be cleared by an attacker with device access.
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
    // Always keep two hashes: current + next. Add the next hash before the
    // cert rotates (Let's Encrypt renews every ~60 days), remove the old
    // one after all clients have updated. A single-hash gap = global outage.
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

        var evalError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &evalError) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let leafCert    = SecTrustGetCertificateAtIndex(serverTrust, 0),
              let publicKey   = SecCertificateCopyKey(leafCert),
              let keyData     = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if Self.pinnedHashes.contains(spkiHash(for: publicKey, keyData: keyData)) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func spkiHash(for key: SecKey, keyData: Data) -> String {
        let attrs   = SecKeyCopyAttributes(key) as? [CFString: Any]
        let keyType = attrs?[kSecAttrKeyType]      as? String ?? ""
        let keySize = attrs?[kSecAttrKeySizeInBits] as? Int ?? 0

        let header: Data
        if keyType == (kSecAttrKeyTypeRSA as String) && keySize == 2048 {
            header = Data([0x30,0x82,0x01,0x22,0x30,0x0d,0x06,0x09,
                           0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,
                           0x01,0x05,0x00,0x03,0x82,0x01,0x0f,0x00])
        } else if keyType == (kSecAttrKeyTypeRSA as String) && keySize == 4096 {
            header = Data([0x30,0x82,0x02,0x22,0x30,0x0d,0x06,0x09,
                           0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,
                           0x01,0x05,0x00,0x03,0x82,0x02,0x0f,0x00])
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) && keySize == 256 {
            header = Data([0x30,0x59,0x30,0x13,0x06,0x07,0x2a,0x86,
                           0x48,0xce,0x3d,0x02,0x01,0x06,0x08,0x2a,
                           0x86,0x48,0xce,0x3d,0x03,0x01,0x07,0x03,
                           0x42,0x00])
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) && keySize == 384 {
            header = Data([0x30,0x76,0x30,0x10,0x06,0x07,0x2a,0x86,
                           0x48,0xce,0x3d,0x02,0x01,0x06,0x05,0x2b,
                           0x81,0x04,0x00,0x22,0x03,0x62,0x00])
        } else {
            return Data(SHA256.hash(data: keyData)).base64EncodedString()
        }

        return Data(SHA256.hash(data: header + keyData)).base64EncodedString()
    }
}
