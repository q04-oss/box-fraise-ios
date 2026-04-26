import Foundation
import Observation

@Observable
final class AppState {
    var member: FraiseMember?       = nil
    var invitations: [FraiseInvitation] = []
    var pushToken: String?          = nil
    var pendingScreen: String?      = nil

    // MARK: - Computed

    var isSignedIn: Bool  { member != nil }
    var hasCredit: Bool   { (member?.creditBalance ?? 0) > 0 }

    var pendingInvitations: [FraiseInvitation] {
        invitations.filter { $0.isPending }
    }
    var activeInvitations: [FraiseInvitation] {
        invitations.filter { $0.isActive }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard let token = Keychain.memberToken else { return }
        async let me   = try? await APIClient.shared.fetchMe(token: token)
        async let invs = try? await APIClient.shared.fetchInvitations(token: token)
        if let m = await me { member = m }
        invitations = await invs ?? []
    }

    // MARK: - Auth

    func signIn(member: FraiseMember) async {
        guard let token = member.token else { return }
        Keychain.memberToken = token
        self.member = member
        invitations = (try? await APIClient.shared.fetchInvitations(token: token)) ?? []
        if let pt = pushToken {
            try? await APIClient.shared.updatePushToken(pt, token: token)
        }
    }

    func signOut() {
        Keychain.memberToken = nil
        member = nil
        invitations = []
    }

    // MARK: - Refresh

    func refreshMe() async {
        guard let token = Keychain.memberToken else { return }
        if let m = try? await APIClient.shared.fetchMe(token: token) { member = m }
    }

    func refreshInvitations() async {
        guard let token = Keychain.memberToken else { return }
        invitations = (try? await APIClient.shared.fetchInvitations(token: token)) ?? []
    }

    // MARK: - Push token

    func registerPushToken(_ token: String) async {
        pushToken = token
        guard let sessionToken = Keychain.memberToken else { return }
        try? await APIClient.shared.updatePushToken(token, token: sessionToken)
    }
}
