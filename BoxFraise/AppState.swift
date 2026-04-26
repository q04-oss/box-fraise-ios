import Foundation
import Observation

@Observable
final class AppState {
    var member: FraiseMember?            = nil
    var invitations: [FraiseInvitation]  = []
    var pushToken: String?               = nil
    var pendingScreen: String?           = nil

    // MARK: - Computed

    var isSignedIn: Bool { member != nil }
    var hasCredit: Bool  { (member?.creditBalance ?? 0) > 0 }

    var pendingInvitations: [FraiseInvitation] { invitations.filter { $0.isPending } }
    var activeInvitations:  [FraiseInvitation] { invitations.filter { $0.isActive  } }

    // MARK: - Cache keys

    private static let memberCacheKey      = "cached_member"
    private static let invitationsCacheKey = "cached_invitations"

    // MARK: - Bootstrap

    func bootstrap() async {
        // Show cached data immediately so the UI is never blank on cold launch
        loadCache()

        guard let token = Keychain.memberToken else { return }
        async let me   = try? await APIClient.shared.fetchMe(token: token)
        async let invs = try? await APIClient.shared.fetchInvitations(token: token)
        if let m = await me {
            member = m
            persist(member: m)
        }
        let fetched = await invs ?? []
        invitations = fetched
        persist(invitations: fetched)
    }

    // MARK: - Auth

    func signIn(member: FraiseMember) async {
        guard let token = member.token else { return }
        Keychain.memberToken = token
        self.member = member
        persist(member: member)
        let fetched = (try? await APIClient.shared.fetchInvitations(token: token)) ?? []
        invitations = fetched
        persist(invitations: fetched)
        if let pt = pushToken {
            try? await APIClient.shared.updatePushToken(pt, token: token)
        }
    }

    func signOut() {
        Keychain.memberToken = nil
        member = nil
        invitations = []
        UserDefaults.standard.removeObject(forKey: Self.memberCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.invitationsCacheKey)
    }

    // MARK: - Refresh

    func refreshMe() async {
        guard let token = Keychain.memberToken else { return }
        if let m = try? await APIClient.shared.fetchMe(token: token) {
            member = m
            persist(member: m)
        }
    }

    func refreshInvitations() async {
        guard let token = Keychain.memberToken else { return }
        let fetched = (try? await APIClient.shared.fetchInvitations(token: token)) ?? []
        invitations = fetched
        persist(invitations: fetched)
    }

    // MARK: - Push token

    func registerPushToken(_ token: String) async {
        pushToken = token
        guard let sessionToken = Keychain.memberToken else { return }
        try? await APIClient.shared.updatePushToken(token, token: sessionToken)
    }

    // MARK: - Cache helpers

    private func loadCache() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: Self.memberCacheKey),
           let m = try? decoder.decode(FraiseMember.self, from: data) {
            member = m
        }
        if let data = UserDefaults.standard.data(forKey: Self.invitationsCacheKey),
           let invs = try? decoder.decode([FraiseInvitation].self, from: data) {
            invitations = invs
        }
    }

    private func persist(member: FraiseMember) {
        if let data = try? JSONEncoder().encode(member) {
            UserDefaults.standard.set(data, forKey: Self.memberCacheKey)
        }
    }

    private func persist(invitations: [FraiseInvitation]) {
        if let data = try? JSONEncoder().encode(invitations) {
            UserDefaults.standard.set(data, forKey: Self.invitationsCacheKey)
        }
    }
}
