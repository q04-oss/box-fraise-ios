import Foundation

extension APIClient {

    // MARK: - Meet / connections

    func getMeetingToken(token: FraiseToken) async throws -> MeetingToken {
        try await request("/connections/token", method: "POST", token: token)
    }

    func recordMeeting(myToken: String, theirToken: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/connections/meet", method: "POST", body: [
            "my_token": myToken, "their_token": theirToken,
        ], token: token)
    }

    func fetchPendingConnections(token: FraiseToken) async throws -> [PendingConnection] {
        try await request("/connections/pending", token: token)
    }

    func approveConnection(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/connections/approve/\(id)",
                                               method: "POST", token: token)
    }

    func declineConnection(id: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/connections/decline/\(id)",
                                               method: "POST", token: token)
    }

    func fetchContacts(token: FraiseToken) async throws -> [FraiseContact] {
        try await request("/connections/contacts", token: token)
    }
}
