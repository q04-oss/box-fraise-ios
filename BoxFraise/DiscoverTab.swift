import SwiftUI

struct DiscoverTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @State private var showCredits = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    onboardingSection
                    if appState.isSignedIn && !appState.activeInvitations.isEmpty {
                        invitationsSection
                    }
                }
                .padding(Spacing.lg)
            }
            .background(c.background)
            .navigationTitle("discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
            .refreshable { await appState.bootstrap() }
        }
        .sheet(isPresented: $showCredits) {
            CreditsView()
        }
    }

    // MARK: - Onboarding

    @ViewBuilder
    private var onboardingSection: some View {
        if !appState.isSignedIn {
            FraiseCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("box fraise")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(c.text)
                    Text("a private network. you don't browse. you get invited.")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                    NavigationLink(destination: AccountTab()) {
                        Text("sign in →")
                            .font(.mono(12))
                            .foregroundStyle(c.text)
                    }
                }
                .padding(Spacing.md)
            }
        } else if !appState.hasCredit {
            FraiseCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("get a credit to be considered.")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(c.text)
                    Text("holding a credit puts you in the pool. businesses browse the member list and invite people they want in the room.")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                    Button("buy a credit — CA$120 →") { showCredits = true }
                        .font(.mono(12))
                        .foregroundStyle(c.text)
                }
                .padding(Spacing.md)
            }
        } else if appState.activeInvitations.isEmpty {
            FraiseCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("you're eligible.")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(c.text)
                    Text("businesses can see you. invitations arrive here when one is extended.")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                }
                .padding(Spacing.md)
            }
        }
    }

    // MARK: - Invitations preview

    private var invitationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionLabel(text: "invitations")
            FraiseCard {
                ForEach(Array(appState.activeInvitations.prefix(3).enumerated()), id: \.element.id) { index, inv in
                    NavigationLink(destination: InvitationDetailView(invitation: inv)) {
                        InvitationRow(invitation: inv, showBorder: index > 0)
                    }
                    .buttonStyle(.plain)
                }
            }
            if appState.activeInvitations.count > 3 {
                Text("see all in claims →")
                    .font(.mono(11))
                    .foregroundStyle(c.muted)
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
                    .font(.mono(13, weight: .medium))
                    .foregroundStyle(c.text)
                Text(invitation.businessName)
                    .font(.mono(11))
                    .foregroundStyle(c.muted)
            }
            Spacer()
            StatusBadge(status: invitation.status)
        }
        .padding(Spacing.md)
        .overlay(alignment: .top) {
            if showBorder {
                Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            }
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
        Text(label)
            .font(.mono(10))
            .foregroundStyle(color)
            .tracking(0.5)
    }
}
