import Foundation
import Security
import LocalAuthentication

enum Keychain {
    private static let service = "com.boxfraise.app"
    private static let tokenKey = "box_fraise_token"

    // MARK: - Public API

    /// Read token — requires biometric auth on devices with a passcode set.
    static var userToken: String? {
        get { read(key: tokenKey) }
        set {
            if let value = newValue { save(key: tokenKey, value: value) }
            else { delete(key: tokenKey) }
        }
    }

    // MARK: - Save

    private static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Build access control: biometry OR device passcode, this device only
        var cfError: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryAny, .or, .devicePasscode],
            &cfError
        )
        if access == nil {
            // Access control creation failed — fall back to storing without biometry
        }

        var deleteQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        service,
            kSecAttrAccount:        key,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        if let access { deleteQuery[kSecAttrAccessControl] = access }
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrService:        service,
            kSecAttrAccount:        key,
            kSecValueData:          data,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        if let access { addQuery[kSecAttrAccessControl] = access }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Save failed (e.g., device has no passcode set) — token will not persist
        }
    }

    // MARK: - Read

    private static func read(key: String) -> String? {
        let context = LAContext()
        context.localizedReason = "authenticate to access box fraise"

        let query: [CFString: Any] = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrService:            service,
            kSecAttrAccount:            key,
            kSecReturnData:             true,
            kSecMatchLimit:             kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
            kSecUseOperationPrompt:     "authenticate to access box fraise" as CFString,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    private static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Metadata (no biometry — for non-sensitive app keys like AppAttest ID)

    static func saveMetadata(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let account = "meta_\(key)"
        let del: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        SecItemDelete(del as CFDictionary)
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func readMetadata(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: "meta_\(key)", kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteMetadata(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: "meta_\(key)",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
