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
                            LabeledSection(title: "pending",   items: appState.invitations.filter { $0.isPending })   { inv, border in row(inv, border) }
                            LabeledSection(title: "accepted",  items: appState.invitations.filter { $0.isAccepted })  { inv, border in row(inv, border) }
                            LabeledSection(title: "confirmed", items: appState.invitations.filter { $0.isConfirmed }) { inv, border in row(inv, border) }
                            LabeledSection(title: "declined",  items: appState.invitations.filter { $0.isDeclined })  { inv, border in row(inv, border) }
                        }
                        .padding(Spacing.lg)
                    }
                    .refreshable { await appState.refreshInvitations() }
                }
            }
            .background(c.background)
            .fraiseNav("invited")
        }
    }

    private func row(_ inv: FraiseInvitation, _ showBorder: Bool) -> some View {
        NavigationLink(destination: InvitationDetailView(invitation: inv)) {
            InvitationRow(invitation: inv, showBorder: showBorder)
        }
        .buttonStyle(.plain)
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
                Text(invitation.title).font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                Text(invitation.businessName).font(.mono(11)).foregroundStyle(c.muted)
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
        status == "confirmed" ? Color(hex: "27AE60") : Color(hex: "8E8E93")
    }

    var body: some View {
        Text(label).font(.mono(10)).foregroundStyle(color).tracking(0.5)
    }
}
