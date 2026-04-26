import Foundation

// MARK: - Errors

enum APIError: LocalizedError {
    case serverError(String)
    case unauthorized
    case notFound
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        case .unauthorized:         return "invalid or expired session"
        case .notFound:             return "not found"
        case .http(let code):       return "HTTP \(code)"
        }
    }
}

// MARK: - Client

actor APIClient {
    static let shared = APIClient()

    private let base = URL(string: "https://fraise.box/api/fraise")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - Core request

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil,
        token: String? = nil
    ) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue(token, forHTTPHeaderField: "x-member-token") }
        if let body  { req.httpBody = try? JSONEncoder().encode(AnyEncodable(body)) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch status {
        case 200...299: break
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default:
            let msg = (try? decoder.decode([String: String].self, from: data))?["error"] ?? "HTTP \(status)"
            throw APIError.serverError(msg)
        }

        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> FraiseMember {
        try await request("/members/login", method: "POST", body: ["email": email, "password": password])
    }

    func signup(name: String, email: String, password: String) async throws -> FraiseMember {
        try await request("/members/signup", method: "POST", body: ["name": name, "email": email, "password": password])
    }

    func appleSignIn(identityToken: String, name: String?, email: String?) async throws -> FraiseMember {
        var body: [String: String] = ["identityToken": identityToken]
        if let name  { body["name"]  = name }
        if let email { body["email"] = email }
        return try await request("/members/apple-signin", method: "POST", body: body)
    }

    // MARK: - Member

    func fetchMe(token: String) async throws -> FraiseMember {
        try await request("/members/me", token: token)
    }

    func updatePushToken(_ pushToken: String, token: String) async throws {
        let _: OKResponse = try await request("/members/push-token", method: "PUT", body: ["push_token": pushToken], token: token)
    }

    // MARK: - Invitations

    func fetchInvitations(token: String) async throws -> [FraiseInvitation] {
        let r: InvitationsResponse = try await request("/members/invitations", token: token)
        return r.invitations
    }

    func acceptInvitation(eventId: Int, token: String) async throws -> AcceptResponse {
        try await request("/members/invitations/\(eventId)/accept", method: "POST", token: token)
    }

    func declineInvitation(eventId: Int, token: String) async throws -> DeclineResponse {
        try await request("/members/invitations/\(eventId)/decline", method: "POST", token: token)
    }

    // MARK: - Credits

    func creditsCheckout(credits: Int, token: String) async throws -> CheckoutResponse {
        try await request("/members/credits/checkout", method: "POST", body: ["credits": credits], token: token)
    }

    func creditsConfirm(paymentIntentId: String, token: String) async throws -> CreditsConfirmResponse {
        try await request("/members/credits/confirm", method: "POST", body: ["payment_intent_id": paymentIntentId], token: token)
    }

    // MARK: - Directory

    func fetchDirectory(token: String) async throws -> [FraiseMemberPublic] {
        let r: DirectoryResponse = try await request("/members/directory", token: token)
        return r.members
    }
}

// MARK: - Helpers

private struct OKResponse: Decodable { let ok: Bool }

// Allows encoding any Encodable as body without generics leaking everywhere
private struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init(_ value: Encodable) { encode = value.encode }
    func encode(to encoder: Encoder) throws { try encode(encoder) }
}
