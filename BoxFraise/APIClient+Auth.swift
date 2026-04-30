import Foundation

extension APIClient {

    // MARK: - Authentication

    func appleSignIn(identityToken: String, firstName: String?, lastName: String?, email: String?) async throws -> AuthResponse {
        var body: [String: Any] = ["identityToken": identityToken]
        if let firstName { body["firstName"] = firstName }
        if let lastName  { body["lastName"]  = lastName }
        if let email     { body["email"]     = email }
        return try await request("/users/apple-signin", method: "POST", body: body)
    }

    func fetchMe(token: FraiseToken) async throws -> BoxUser {
        try await request("/users/me", token: token)
    }

    func updatePushToken(_ pushToken: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/users/push-token", method: "PUT",
                                               body: ["push_token": pushToken], token: token)
    }

    func fetchSocialAccess(token: FraiseToken) async throws -> UserSocialAccess {
        try await request("/users/me/social-access", token: token)
    }

    func updateStatus(_ status: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/users/me/status", method: "PATCH",
                                               body: ["status": status], token: token)
    }

    func setDateOptIn(_ open: Bool, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/dates/opt-in", method: "PATCH",
                                               body: ["open": open], token: token)
    }

    // MARK: - Password reset

    func forgotPassword(email: String) async throws {
        let _: OKResponse = try await request("/auth/forgot-password", method: "POST",
                                               body: ["email": email])
    }

    func resetPassword(token: String, newPassword: String) async throws {
        let _: OKResponse = try await request("/auth/reset-password", method: "POST",
                                               body: ["token": token, "new_password": newPassword])
    }
}
