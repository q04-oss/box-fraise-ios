import Foundation
import CryptoKit

// MARK: - Error

enum APIError: LocalizedError {
    case serverError(String)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case pinningFailure

    var errorDescription: String? {
        switch self {
        case .serverError(let m):         return m
        case .unauthorized:               return "session expired — please sign in again"
        case .rateLimited(let after):     return "too many requests — try again in \(Int(after))s"
        case .http(let c):                return "HTTP \(c)"
        case .pinningFailure:             return "secure connection could not be established"
        }
    }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    // URL is a compile-time constant — if this fails the app cannot function at all.
    private let base: URL = URL(string: "https://fraise.box/api") ?? { fatalError("invalid base URL") }()

    // Pinned URLSession — used for ALL requests
    private let session: URLSession = {
        let delegate = PinningDelegate()
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // HMAC request-signing key — generated once per device on first launch and stored in
    // Keychain so it never appears in the binary's data segment or in strings output.
    // The server learns this key during App Attest registration (sent as hmacKey in
    // registerAttestation). Attested devices additionally sign every request with an
    // ECDSA assertion from the Secure Enclave — HMAC is the fallback for unattested devices.
    private static let signingKey: SymmetricKey = {
        let service = "com.boxfraise.hmac"
        let account = "request-signing-v2"
        // Load existing device-specific key from Keychain.
        let loadQ: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        var result: AnyObject?
        if SecItemCopyMatching(loadQ as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        // First launch — generate a random 256-bit device-unique key.
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let saveQ: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     service,
            kSecAttrAccount:     account,
            kSecValueData:       keyData,
            kSecAttrAccessible:  kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any,
        ]
        SecItemAdd(saveQ as CFDictionary, nil)
        return newKey
    }()

    // Exposes the device signing key bytes for registration during App Attest.
    // The server learns this key so it can validate per-device HMAC signatures independently.
    var deviceSigningKeyData: Data {
        Self.signingKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - Core request
    // Typed: JSON-encodes body, HMAC-signs, App Attest asserts, JSON-decodes response via decoder.

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: FraiseToken? = nil
    ) async throws -> T {
        // Direct string construction avoids appendingPathComponent stripping leading slashes.
        guard let url = URL(string: "https://fraise.box/api\(path)") else {
            throw APIError.serverError("invalid path: \(path)")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30  // surface failures faster than the 60s default
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Fraise-Client")
        if let token { req.setValue("Bearer \(token.rawValue)", forHTTPHeaderField: "Authorization") }

        let bodyData: Data
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = bodyData
        } else {
            bodyData = Data()
        }

        // HMAC-SHA256 over: method + fullPath + timestamp + body
        //   method    — prevents method substitution (GET → POST)
        //   fullPath  — prevents path substitution (/orders → /admin)
        //   timestamp — replay window: server rejects requests older than 5 minutes
        //   body      — prevents body tampering after signing
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let fullPath = "/api\(path)"
        let message = "\(method)\(fullPath)\(timestamp)".data(using: .utf8)! + bodyData
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: Self.signingKey)
        req.setValue(timestamp, forHTTPHeaderField: "X-Fraise-Ts")
        req.setValue(Data(mac).base64EncodedString(), forHTTPHeaderField: "X-Fraise-Sig")

        // App Attest assertion — layered on top of HMAC for attested devices
        if let assertion = await AppAttest.shared.assertion(for: message) {
            req.setValue(assertion, forHTTPHeaderField: "X-Fraise-Assertion")
            if let kid = await AppAttest.shared.keyID {
                req.setValue(kid, forHTTPHeaderField: "X-Fraise-Attest-Key")
            }
        }

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if !(200...299).contains(status) {
            if status == 401 { throw APIError.unauthorized }
            if status == 429 {
                let retryAfter = (response as? HTTPURLResponse)
                    .flatMap { $0.value(forHTTPHeaderField: "Retry-After") }
                    .flatMap { TimeInterval($0) } ?? 60
                throw APIError.rateLimited(retryAfter: retryAfter)
            }
            let msg = (try? Self.decoder.decode([String: String].self, from: data))?["error"]
            throw APIError.serverError(msg ?? "HTTP \(status)")
        }

        return try Self.decoder.decode(T.self, from: data)
    }

    // Raw: caller provides pre-encoded body and handles decoded response — used where custom
    // auth headers are needed (staff pin, walk-in NFC token) rather than a Bearer token.
    func rawRequest(url: URL, method: String = "GET",
                    headers: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15  // local-network staff/walk-in endpoints should respond faster
        req.httpMethod = method
        req.setValue("ios", forHTTPHeaderField: "X-Fraise-Client")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = body

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let path = url.path
        let message = "\(method)\(path)\(timestamp)".data(using: .utf8)! + (body ?? Data())
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: Self.signingKey)
        req.setValue(timestamp, forHTTPHeaderField: "X-Fraise-Ts")
        req.setValue(Data(mac).base64EncodedString(), forHTTPHeaderField: "X-Fraise-Sig")

        let (data, _) = try await session.data(for: req)
        return data
    }

    // MARK: - Staff

    func fetchStaffOrders(pin: String, token: FraiseToken) async throws -> [StaffOrder] {
        let url = URL(string: "https://fraise.box/api/staff/orders") ?? base
        let data = try await rawRequest(url: url, headers: [
            "x-staff-pin":   pin,
            "Authorization": "Bearer \(token.rawValue)",
        ])
        return try Self.decoder.decode([StaffOrder].self, from: data)
    }

    func staffAction(_ action: String, orderId: Int, pin: String) async throws {
        let url = URL(string: "https://fraise.box/api/staff/orders/\(orderId)/\(action)") ?? base
        _ = try? await rawRequest(url: url, method: "PATCH", headers: ["x-staff-pin": pin])
    }

    // MARK: - Walk-in

    func fetchWalkInInventory(locationId: Int) async throws -> [WalkInItem] {
        let url = URL(string: "https://fraise.box/api/walkin/inventory?location_id=\(locationId)") ?? base
        let data = try await rawRequest(url: url)
        return (try? Self.decoder.decode([WalkInItem].self, from: data)) ?? []
    }

    func createWalkInOrder(nfcToken: String, chocolate: String, finish: String,
                           customerEmail: String) async throws -> JoinResponse {
        let url = URL(string: "https://fraise.box/api/walkin/\(nfcToken)/order") ?? base
        let body = try JSONSerialization.data(withJSONObject: [
            "chocolate":      chocolate,
            "finish":         finish,
            "customer_email": customerEmail,
        ])
        let data = try await rawRequest(url: url, method: "POST",
                                        headers: ["Content-Type": "application/json"], body: body)
        return try Self.decoder.decode(JoinResponse.self, from: data)
    }
}

// MARK: - Response helpers

struct OKResponse: Decodable { let ok: Bool? }

struct PopupsResponse: Decodable { let popups: [FraisePopup] }

// Stripe client secret — must never appear in logs.
struct JoinResponse: Decodable, CustomDebugStringConvertible {
    let clientSecret: String
    var debugDescription: String { "JoinResponse(clientSecret: [REDACTED])" }
}
