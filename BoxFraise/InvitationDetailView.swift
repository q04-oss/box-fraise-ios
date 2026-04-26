import SwiftUI

struct InvitationDetailView: View {
    let invitation: FraiseInvitation

    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.dismiss) var dismiss

    @State private var loading = false
    @State private var error: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(invitation.businessName).font(.mono(11)).foregroundStyle(c.muted).tracking(0.5)
                    Text(invitation.title).font(.mono(20, weight: .medium)).foregroundStyle(c.text)
                }

                if let desc = invitation.description, !desc.isEmpty {
                    Text(desc).font(.mono(13)).foregroundStyle(c.muted).lineSpacing(5)
                }

                CardRows(rows: [
                    "status":    invitation.status,
                    "price":     "CA$\(invitation.priceCents / 100)",
                    "seats":     "\(invitation.seatsClaimed) / \(invitation.maxSeats)",
                    "date":      invitation.eventDate ?? "tbd — set when threshold met",
                    "threshold": "\(invitation.minSeats) minimum",
                ])

                if let error { ErrorText(message: error) }

                actionButtons
            }
            .padding(Spacing.lg)
        }
        .background(c.background)
        .navigationTitle("invitation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(c.background, for: .navigationBar)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if invitation.isPending {
            VStack(spacing: Spacing.sm) {
                Text("accepting spends 1 credit. you have \(appState.member?.creditBalance ?? 0).")
                    .font(.mono(11)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
                PrimaryButton(label: "accept →", loading: loading) { Task { await accept() } }
                GhostButton(label: "decline") { Task { await decline() } }
            }
        } else if invitation.isAccepted {
            VStack(spacing: Spacing.sm) {
                Text("you've accepted. waiting for the date to be confirmed.")
                    .font(.mono(11)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
                GhostButton(label: "decline (credit returned)") { Task { await decline() } }
            }
        } else if invitation.isConfirmed {
            CardRows(rows: ["confirmed": invitation.eventDate ?? "date tbd"])
        }
    }

    private func accept() async {
        guard let token = Keychain.memberToken else { return }
        loading = true; error = nil
        do { _ = try await APIClient.shared.acceptInvitation(eventId: invitation.eventId, token: token)
             await appState.refreshInvitations(); await appState.refreshMe(); dismiss() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func decline() async {
        guard let token = Keychain.memberToken else { return }
        loading = true; error = nil
        do { _ = try await APIClient.shared.declineInvitation(eventId: invitation.eventId, token: token)
             await appState.refreshInvitations(); await appState.refreshMe(); dismiss() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
