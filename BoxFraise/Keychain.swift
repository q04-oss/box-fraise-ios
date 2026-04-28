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

    // MARK: - withToken

    // Eliminates the `guard let token = Keychain.userToken else { return }` pattern
    // that otherwise appears at the top of every async panel function.

    /// Throwing variant — use with `try await` where callers handle errors.
    @discardableResult
    static func withToken<T>(_ body: (String) async throws -> T) async throws -> T {
        guard let token = userToken else { throw APIError.unauthorized }
        return try await body(token)
    }

    /// Non-throwing variant — use where the call site already ignores errors.
    static func withToken(_ body: (String) async -> Void) async {
        guard let token = userToken else { return }
        await body(token)
    }

    // MARK: - Metadata (no biometry — for non-sensitive app keys like AppAttest ID)

    @discardableResult
    static func saveMetadata(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let account = "meta_\(key)"
        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        // Item doesn't exist yet — add it.
        let add: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
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
