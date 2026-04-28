import SwiftUI

struct ProfilePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var earnings: UserEarnings?
    @State private var showPreferences = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FraiseBackButton { state.panel = .home }

                if let user = state.user {

                    // ── Avatar + name ─────────────────────────────────────────
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle().fill(c.card)
                                .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                                .frame(width: 56, height: 56)
                            Text(user.initial)
                                .font(.system(size: 22, design: .serif))
                                .foregroundStyle(c.text)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.displayName?.lowercased() ?? "member")
                                .font(.system(size: 22, design: .serif))
                                .foregroundStyle(c.text)
                            if user.verified {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10)).foregroundStyle(c.muted)
                                    Text("verified")
                                        .font(.mono(10)).foregroundStyle(c.muted).tracking(0.5)
                                }
                            }
                        }
                    }

                    // ── Social identity (verified users) ─────────────────────
                    if user.verified {
                        VStack(spacing: 0) {
                            if let email = user.fraiseChatEmail {
                                Button { state.panel = .messages } label: {
                                    socialRow(email, label: "messages", icon: "at")
                                        .overlay(alignment: .trailing) {
                                            if state.totalUnreadMessages > 0 {
                                                Text("\(state.totalUnreadMessages)")
                                                    .font(.mono(9)).foregroundStyle(c.background)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(c.text).clipShape(Capsule())
                                                    .padding(.trailing, Spacing.md)
                                            }
                                        }
                                }
                            }
                            if let tier = state.socialAccess?.tier ?? user.socialTier {
                                socialRow(tier.replacingOccurrences(of: "_", with: " ").lowercased(),
                                          label: "tier", icon: "chart.bar.fill")
                            }
                            if let days = state.socialAccess?.bankDays {
                                socialRow("\(days) days", label: "bank", icon: "clock")
                            }
                            if let streak = user.currentStreakWeeks, streak > 0 {
                                socialRow("week \(streak)", label: "streak", icon: "flame")
                            }
                            if let balance = earnings?.balanceCents, balance > 0 {
                                socialRow("CA$\(String(format: "%.2f", Double(balance) / 100))",
                                          label: "earned", icon: "banknote")
                            }
                        }
                        .background(c.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
                    }

                    // ── Links ─────────────────────────────────────────────────
                    VStack(spacing: 0) {
                        profileLink("akène", icon: "leaf") {
                            state.panel = .akene
                        }
                        profileLink("preferences", icon: "slider.horizontal.3") {
                            showPreferences = true
                        }
                        profileLink("order history", icon: "clock.arrow.circlepath") {
                            state.panel = .orderHistory
                        }
                        profileLink("met", icon: "person.2.wave.2") {
                            state.panel = .meet
                        }
                        profileLink("referrals", icon: "person.2") {
                            state.panel = .referrals
                        }
                        profileLink("verify pickup", icon: "checkmark.seal") {
                            state.panel = .nfcVerify
                        }
                        if user.verified {
                            profileLink("standing orders", icon: "arrow.clockwise.circle") {
                                state.panel = .standingOrders
                            }
                        }
                        if user.isShop {
                            profileLink("staff orders", icon: "person.badge.key") {
                                state.panel = .staff
                            }
                        }
                    }
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))

                    // ── Sign out ──────────────────────────────────────────────
                    Button { state.signOut() } label: {
                        Text("sign out")
                            .font(.mono(12)).foregroundStyle(Color.fraiseRed)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.fraiseRed.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                            .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(
                                Color.fraiseRed.opacity(0.2), lineWidth: 0.5))
                    }

                } else {
                    FraiseEmptyState(
                        icon: "person.circle",
                        title: "not signed in",
                        subtitle: "sign in to place orders, join popups, and verify your pickup."
                    )
                    Button { state.panel = .auth } label: {
                        HStack {
                            Text("sign in").font(.mono(13, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                        .background(c.text).clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
        .refreshable { await reloadProfile() }
        .sheet(isPresented: $showPreferences) {
            PreferencesSheet()
                .fraiseTheme()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .task { await reloadProfile() }
    }

    @MainActor private func reloadProfile() async {
        await state.refreshUser()
        await Keychain.withToken { token in
            earnings = try? await APIClient.shared.fetchEarnings(token: token)
        }
    }

    private func socialRow(_ value: String, label: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13)).foregroundStyle(c.muted).frame(width: 20)
            Text(label)
                .font(.mono(10)).foregroundStyle(c.muted).tracking(1).textCase(.uppercase)
                .frame(width: 64, alignment: .leading)
            Text(value).font(.mono(13)).foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }

    private func profileLink(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14)).foregroundStyle(c.muted).frame(width: 20)
                Text(label).font(.mono(13)).foregroundStyle(c.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.border)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            }
        }
    }
}

// MARK: - Preferences sheet

private struct PreferencesSheet: View {
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
        var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("preferences")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Button("done") { dismiss() }
                    .font(.mono(12)).foregroundStyle(c.muted)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13)).foregroundStyle(c.muted).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("open to dates")
                            .font(.mono(13)).foregroundStyle(c.text)
                        Text("businesses can invite you to sponsored dinners")
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $state.openToDates)
                        .labelsHidden().tint(c.text)
                        .onChange(of: state.openToDates) { _, val in
                            Task {
                                guard let token = Keychain.userToken else { return }
                                try? await APIClient.shared.setDateOptIn(val, token: token)
                            }
                        }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 16)
            }
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
            .padding(Spacing.md)

            Spacer()
        }
        .background(c.background.ignoresSafeArea())
    }
}
