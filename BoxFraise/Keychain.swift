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
        var error: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            [.biometryAny, .or, .devicePasscode],
            &error
        )

        var query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     key,
            kSecValueData:       data,
            kSecAttrSynchronizable: kCFBooleanFalse as Any, // no iCloud sync
        ]

        if let access {
            query[kSecAttrAccessControl] = access
        }

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
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
}
