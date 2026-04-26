import SwiftUI

struct InvitationsTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isSignedIn {
                    EmptyStateView("sign in to see your invitations.")
                } else if appState.activeInvitations.isEmpty {
                    EmptyStateView("no invitations yet.")
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            group("pending",   appState.invitations.filter { $0.isPending })
                            group("accepted",  appState.invitations.filter { $0.isAccepted })
                            group("confirmed", appState.invitations.filter { $0.isConfirmed })
                            group("declined",  appState.invitations.filter { $0.isDeclined })
                        }
                        .padding(Spacing.lg)
                    }
                    .refreshable { await appState.refreshInvitations() }
                }
            }
            .background(c.background)
            .navigationTitle("claims")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ invitations: [FraiseInvitation]) -> some View {
        if !invitations.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionLabel(text: title)
                FraiseCard {
                    ForEach(Array(invitations.enumerated()), id: \.element.id) { i, inv in
                        NavigationLink(destination: InvitationDetailView(invitation: inv)) {
                            InvitationRow(invitation: inv, showBorder: i > 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
