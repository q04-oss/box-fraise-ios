import SwiftUI

struct InvitationsTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isSignedIn {
                    emptyState("sign in to see your invitations.")
                } else if appState.activeInvitations.isEmpty {
                    emptyState("no invitations yet.")
                } else {
                    list
                }
            }
            .background(c.background)
            .navigationTitle("claims")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
            .refreshable { await appState.refreshInvitations() }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                let pending   = appState.invitations.filter { $0.isPending }
                let accepted  = appState.invitations.filter { $0.isAccepted }
                let confirmed = appState.invitations.filter { $0.isConfirmed }
                let declined  = appState.invitations.filter { $0.isDeclined }

                if !pending.isEmpty   { group("pending",   invitations: pending) }
                if !accepted.isEmpty  { group("accepted",  invitations: accepted) }
                if !confirmed.isEmpty { group("confirmed", invitations: confirmed) }
                if !declined.isEmpty  { group("declined",  invitations: declined) }
            }
            .padding(Spacing.lg)
        }
    }

    private func group(_ title: String, invitations: [FraiseInvitation]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionLabel(text: title)
            FraiseCard {
                ForEach(Array(invitations.enumerated()), id: \.element.id) { index, inv in
                    NavigationLink(destination: InvitationDetailView(invitation: inv)) {
                        InvitationRow(invitation: inv, showBorder: index > 0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.mono(13))
                .foregroundStyle(c.muted)
            Spacer()
        }
    }
}
