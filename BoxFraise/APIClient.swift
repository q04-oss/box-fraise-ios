import Foundation
import CryptoKit

// MARK: - Error

enum APIError: LocalizedError {
    case serverError(String)
    case unauthorized
    case http(Int)
    case pinningFailure

    var errorDescription: String? {
        switch self {
        case .serverError(let m): return m
        case .unauthorized:       return "session expired — please sign in again"
        case .http(let c):        return "HTTP \(c)"
        case .pinningFailure:     return "secure connection could not be established"
        }
    }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    private let base = URL(string: "https://fraise.box/api")!

    // Pinned URLSession — used for ALL requests
    private let session: URLSession = {
        let delegate = PinningDelegate()
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // HMAC signing secret — stored as bytes so it doesn't appear in binary strings output
    private static let signingKey = SymmetricKey(data: Data([
        0x66, 0x72, 0x61, 0x69, 0x73, 0x65, 0x2d, 0x72,  // fraise-r
        0x65, 0x71, 0x75, 0x65, 0x73, 0x74, 0x2d, 0x73,  // equest-s
        0x69, 0x67, 0x6e, 0x69, 0x6e, 0x67, 0x2d, 0x76,  // igning-v
        0x31,                                              // 1
    ]))

    // MARK: - Core request

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ios", forHTTPHeaderField: "X-Fraise-Client")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let bodyData: Data
        if let body {
            bodyData = try JSONSerialization.data(withJSONObject: body)
            req.httpBody = bodyData
        } else {
            bodyData = Data()
        }

        // HMAC signature: HMAC(key, method + fullPath + timestamp + body)
        // Use full path (/api/...) so both request() and rawRequest() sign identically
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
            let msg = (try? Self.decoder.decode([String: String].self, from: data))?["error"]
            throw APIError.serverError(msg ?? "HTTP \(status)")
        }

        return try Self.decoder.decode(T.self, from: data)
    }

    // Raw request builder — for endpoints needing custom headers (staff, walk-in)
    private func rawRequest(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: url)
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

    // MARK: - Auth

    func appleSignIn(identityToken: String, firstName: String?, lastName: String?, email: String?) async throws -> AuthResponse {
        var body: [String: Any] = ["identityToken": identityToken]
        if let firstName { body["firstName"] = firstName }
        if let lastName  { body["lastName"]  = lastName }
        if let email     { body["email"]     = email }
        return try await request("/users/apple-signin", method: "POST", body: body)
    }

    func fetchMe(token: String) async throws -> BoxUser {
        try await request("/users/me", token: token)
    }

    func registerAttestation(keyID: String, attestation: Data, challenge: Data, userToken: String?) async throws {
        let _: OKResponse = try await request("/devices/attest", method: "POST", body: [
            "key_id":      keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge":   challenge.base64EncodedString(),
        ], token: userToken)
    }

    func updatePushToken(_ pushToken: String, token: String) async throws {
        let _: OKResponse = try await request("/users/push-token", method: "PUT", body: ["push_token": pushToken], token: token)
    }

    // MARK: - Businesses

    func fetchBusinesses() async throws -> [Business] {
        try await request("/businesses")
    }

    // MARK: - Popups

    func fetchPopups() async throws -> [FraisePopup] {
        let response: PopupsResponse = try await request("/fraise/popups")
        return response.popups
    }

    func joinPopup(id: Int, token: String) async throws -> JoinResponse {
        try await request("/fraise/popups/\(id)/join", method: "POST", token: token)
    }

    func confirmPopupJoin(id: Int, token: String) async throws {
        let _: OKResponse = try await request("/fraise/popups/\(id)/join/confirm", method: "POST", token: token)
    }

    func cancelPopup(id: Int, token: String) async throws {
        let _: OKResponse = try await request("/fraise/popups/\(id)/cancel", method: "POST", token: token)
    }

    // MARK: - Varieties

    func fetchVarieties() async throws -> [Variety] {
        try await request("/varieties")
    }

    // MARK: - Orders

    func createOrder(locationId: Int, varietyId: Int, chocolate: String, finish: String, quantity: Int, token: String) async throws -> OrderResponse {
        try await request("/orders", method: "POST", body: [
            "location_id": locationId,
            "variety_id":  varietyId,
            "chocolate":   chocolate,
            "finish":      finish,
            "quantity":    quantity,
        ], token: token)
    }

    func confirmOrder(orderId: Int, paymentIntentId: String, token: String) async throws -> ConfirmedOrder {
        try await request("/orders/\(orderId)/confirm", method: "POST",
            body: ["payment_intent_id": paymentIntentId], token: token)
    }

    func payWithBalance(orderId: Int, token: String) async throws -> ConfirmedOrder {
        try await request("/orders/\(orderId)/pay-balance", method: "POST", token: token)
    }

    func fetchOrderHistory(token: String) async throws -> [PastOrder] {
        try await request("/users/me/orders", token: token)
    }

    func rateOrder(id: Int, rating: Int, token: String) async throws {
        let _: OKResponse = try await request("/orders/\(id)/rate", method: "POST",
            body: ["rating": rating], token: token)
    }

    // MARK: - NFC

    func verifyNFC(token nfcToken: String, userToken: String) async throws -> NFCVerifyResult {
        try await request("/verify/nfc", method: "POST", body: ["nfc_token": nfcToken], token: userToken)
    }

    // MARK: - Staff

    func fetchStaffOrders(pin: String, token: String) async throws -> [StaffOrder] {
        let url = URL(string: "https://fraise.box/api/staff/orders")!
        let data = try await rawRequest(url: url, headers: [
            "x-staff-pin":   pin,
            "Authorization": "Bearer \(token)",
        ])
        return try Self.decoder.decode([StaffOrder].self, from: data)
    }

    func staffAction(_ action: String, orderId: Int, pin: String) async throws {
        let url = URL(string: "https://fraise.box/api/staff/orders/\(orderId)/\(action)")!
        _ = try? await rawRequest(url: url, method: "PATCH", headers: ["x-staff-pin": pin])
    }

    // MARK: - Walk-in

    func fetchWalkInInventory(locationId: Int) async throws -> [WalkInItem] {
        let url = URL(string: "https://fraise.box/api/walkin/inventory?location_id=\(locationId)")!
        let data = try await rawRequest(url: url)
        return (try? Self.decoder.decode([WalkInItem].self, from: data)) ?? []
    }

    func createWalkInOrder(nfcToken: String, chocolate: String, finish: String, customerEmail: String) async throws -> JoinResponse {
        let url = URL(string: "https://fraise.box/api/walkin/\(nfcToken)/order")!
        let body = try JSONSerialization.data(withJSONObject: [
            "chocolate": chocolate,
            "finish": finish,
            "customer_email": customerEmail,
        ])
        let data = try await rawRequest(url: url, method: "POST", headers: [
            "Content-Type": "application/json"
        ], body: body)
        return try Self.decoder.decode(JoinResponse.self, from: data)
    }
}

// MARK: - Response helpers

private struct OKResponse: Decodable { let ok: Bool? }

struct PopupsResponse: Decodable { let popups: [FraisePopup] }

struct JoinResponse: Decodable {
    let clientSecret: String
}
