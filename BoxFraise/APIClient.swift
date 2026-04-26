import Foundation

// MARK: - Error

enum APIError: LocalizedError {
    case serverError(String)
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let m): return m
        case .unauthorized:       return "invalid or expired session"
        case .http(let c):        return "HTTP \(c)"
        }
    }
}

// MARK: - Envelope unwrapper (handles { "key": [...] } responses)

private struct Wrap<T: Decodable>: Decodable {
    let value: T
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let key = c.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty envelope"))
        }
        value = try c.decode(T.self, forKey: key)
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    private let base = URL(string: "https://fraise.box/api/fraise")!

    // MARK: Core

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue(token, forHTTPHeaderField: "x-member-token") }
        if let body  { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if !(200...299).contains(status) {
            if status == 401 { throw APIError.unauthorized }
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw APIError.serverError(msg ?? "HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // Unwraps single-key envelope automatically
    private func requestWrapped<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        token: String? = nil
    ) async throws -> T {
        let w: Wrap<T> = try await request(path, method: method, body: body, token: token)
        return w.value
    }

    // MARK: Auth

    func login(email: String, password: String) async throws -> FraiseMember {
        try await request("/members/login", method: "POST", body: ["email": email, "password": password])
    }

    func signup(name: String, email: String, password: String) async throws -> FraiseMember {
        try await request("/members/signup", method: "POST", body: ["name": name, "email": email, "password": password])
    }

    func appleSignIn(identityToken: String, name: String?, email: String?) async throws -> FraiseMember {
        var body: [String: Any] = ["identityToken": identityToken]
        if let name  { body["name"]  = name }
        if let email { body["email"] = email }
        return try await request("/members/apple-signin", method: "POST", body: body)
    }

    // MARK: Member

    func fetchMe(token: String) async throws -> FraiseMember {
        try await request("/members/me", token: token)
    }

    func updatePushToken(_ pushToken: String, token: String) async throws {
        let _: OKResponse = try await request("/members/push-token", method: "PUT", body: ["push_token": pushToken], token: token)
    }

    // MARK: Invitations

    func fetchInvitations(token: String) async throws -> [FraiseInvitation] {
        try await requestWrapped("/members/invitations", token: token)
    }

    func acceptInvitation(eventId: Int, token: String) async throws {
        let _: OKResponse = try await request("/members/invitations/\(eventId)/accept", method: "POST", token: token)
    }

    func declineInvitation(eventId: Int, token: String) async throws {
        let _: OKResponse = try await request("/members/invitations/\(eventId)/decline", method: "POST", token: token)
    }

    // MARK: Credits

    func creditsCheckout(credits: Int, token: String) async throws -> CheckoutResponse {
        try await request("/members/credits/checkout", method: "POST", body: ["credits": credits], token: token)
    }

    func creditsConfirm(paymentIntentId: String, token: String) async throws {
        let _: OKResponse = try await request("/members/credits/confirm", method: "POST", body: ["payment_intent_id": paymentIntentId], token: token)
    }
}

private struct OKResponse: Decodable { let ok: Bool }
