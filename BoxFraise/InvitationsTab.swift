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
            .navigationTitle("invited")
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

// MARK: - InvitationRow

struct InvitationRow: View {
    let invitation: FraiseInvitation
    var showBorder: Bool = true
    @Environment(\.fraiseColors) var c

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.title)
                    .font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                Text(invitation.businessName)
                    .font(.mono(11)).foregroundStyle(c.muted)
            }
            Spacer()
            StatusBadge(status: invitation.status)
        }
        .padding(Spacing.md)
        .overlay(alignment: .top) {
            if showBorder { Rectangle().frame(height: 0.5).foregroundStyle(c.border) }
        }
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let status: String

    private var label: String {
        switch status {
        case "pending":   return "invited"
        case "accepted":  return "accepted"
        case "confirmed": return "confirmed"
        case "declined":  return "declined"
        default:          return status
        }
    }

    private var color: Color {
        switch status {
        case "confirmed": return Color(hex: "27AE60")
        case "declined":  return Color(hex: "8E8E93")
        default:          return Color(hex: "8E8E93")
        }
    }

    var body: some View {
        Text(label).font(.mono(10)).foregroundStyle(color).tracking(0.5)
    }
}
