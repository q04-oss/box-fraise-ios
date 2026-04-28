import SwiftUI
import StripePaymentSheet

struct AkenePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    @State private var profile: AkeneProfile?
    @State private var leaderboard: [AkeneLeaderboardEntry] = []
    @State private var invitations: [AkeneInvitation] = []
    @State private var loading = false
    @State private var tab: Tab = .rank
    @State private var buySheet: PaymentSheet?
    @State private var buyQuantity = 1
    @State private var showBuySheet = false
    @State private var purchasing = false

    enum Tab { case rank, invitations }

    private var pendingInvitations: [AkeneInvitation] { invitations.filter { $0.isPending } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                Text("akène")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Button {
                    guard let token = Keychain.userToken else { return }
                    Task { await preparePurchase(token: token) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("buy")
                            .font(.mono(11))
                    }
                    .foregroundStyle(c.muted)
                }
                .disabled(purchasing)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // My rank card
            if let p = profile {
                rankCard(p)
            } else if loading {
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card)
                    .frame(height: 90)
                    .padding(.horizontal, Spacing.md)
                    .shimmering()
            }

            // Tab bar
            HStack(spacing: 0) {
                tabButton("leaderboard", selected: tab == .rank) { tab = .rank }
                if !invitations.isEmpty {
                    tabButton("invitations\(pendingInvitations.isEmpty ? "" : " (\(pendingInvitations.count))")",
                              selected: tab == .invitations) { tab = .invitations }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if tab == .rank {
                leaderboardList
            } else {
                invitationsList
            }
        }
        .paymentSheet(isPresented: $showBuySheet, paymentSheet: buySheet ?? PaymentSheet(
            paymentIntentClientSecret: "", configuration: PaymentSheet.Configuration()
        )) { result in
            if case .completed = result {
                Task { await handlePurchaseComplete() }
            }
        }
        .task { await load() }
    }

    // MARK: - Rank card

    private func rankCard(_ p: AkeneProfile) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(p.akeneHeld)")
                        .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)
                    Text(p.akeneHeld == 1 ? "akène" : "akènes")
                        .font(.mono(11)).foregroundStyle(c.muted)
                }
                Text("CA$\(p.akeneHeld * 120) invested")
                    .font(.mono(9)).foregroundStyle(c.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let pos = p.rankPosition {
                    Text("#\(pos)")
                        .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)
                    if let total = p.totalHolders {
                        Text("of \(total)")
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 22, design: .serif)).foregroundStyle(c.muted)
                    Text("no akène yet")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
    }

    // MARK: - Leaderboard

    private var leaderboardList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if leaderboard.isEmpty && !loading {
                    FraiseEmptyState(icon: "chart.bar", title: "no holders yet",
                                     subtitle: "be the first to hold akène.")
                        .padding(.top, 60)
                } else {
                    ForEach(leaderboard) { entry in
                        leaderboardRow(entry)
                        if entry.rankPosition < leaderboard.count {
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, Spacing.md)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    private func leaderboardRow(_ entry: AkeneLeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(entry.rankPosition <= 3 ? c.text : c.card)
                    .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    .frame(width: 36, height: 36)
                Text("#\(entry.rankPosition)")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(entry.rankPosition <= 3 ? c.background : c.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName?.lowercased() ?? "member")
                    .font(.mono(13)).foregroundStyle(c.text)
                HStack(spacing: 8) {
                    Label("\(entry.akeneHeld) akène", systemImage: "leaf")
                        .font(.mono(9)).foregroundStyle(c.muted)
                    Label("\(entry.eventsAttended) evenings", systemImage: "fork.knife")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
            }

            Spacer()

            Text("\(entry.rankScore)")
                .font(.mono(11)).foregroundStyle(c.muted)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
    }

    // MARK: - Invitations

    private var invitationsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                if invitations.isEmpty {
                    FraiseEmptyState(icon: "envelope", title: "no invitations",
                                     subtitle: "hold akène to receive evening invitations.")
                        .padding(.top, 60)
                } else {
                    ForEach(invitations) { inv in
                        invitationCard(inv)
                    }
                }
            }
            .padding(Spacing.md)
        }
    }

    private func invitationCard(_ inv: AkeneInvitation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(inv.title.lowercased())
                        .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                    if let biz = inv.businessName {
                        Text(biz.lowercased())
                            .font(.mono(10)).foregroundStyle(c.muted)
                    }
                }
                Spacer()
                statusPill(inv.status)
            }

            if let desc = inv.description {
                Text(desc.lowercased())
                    .font(.mono(11)).foregroundStyle(c.muted)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                if let date = inv.eventDate {
                    Label(formatDate(date), systemImage: "calendar")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
                Label("\(inv.capacity) capacity", systemImage: "person.2")
                    .font(.mono(9)).foregroundStyle(c.muted)
            }

            if inv.isPending {
                HStack(spacing: Spacing.sm) {
                    Button {
                        Task { await respond(inv.id, accept: false) }
                    } label: {
                        Text("decline")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(c.searchBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        Task { await respond(inv.id, accept: true) }
                    } label: {
                        Text("accept")
                            .font(.mono(12, weight: .medium)).foregroundStyle(c.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(c.text)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            inv.isPending ? c.text.opacity(0.2) : c.border, lineWidth: 0.5))
    }

    private func statusPill(_ status: String) -> some View {
        let color: Color = status == "accepted" ? Color(hex: "4CAF50")
                         : status == "declined"  ? c.muted
                         : c.text
        return Text(status)
            .font(.mono(8)).foregroundStyle(status == "pending" ? c.background : color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status == "pending" ? c.text : color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Actions

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        async let p  = try? await APIClient.shared.fetchAkeneProfile(token: token)
        async let lb = try? await APIClient.shared.fetchAkeneLeaderboard(token: token)
        async let iv = try? await APIClient.shared.fetchAkeneInvitations(token: token)
        if let v = await p  { profile = v }
        if let v = await lb { leaderboard = v }
        if let v = await iv { invitations = v }
        loading = false
    }

    @MainActor private func preparePurchase(token: String) async {
        purchasing = true
        do {
            let resp = try await APIClient.shared.purchaseAkene(quantity: buyQuantity, token: token)
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Box Fraise"
            config.defaultBillingDetails.address.country = "CA"
            buySheet = PaymentSheet(paymentIntentClientSecret: resp.clientSecret, configuration: config)
            showBuySheet = true
        } catch {
            Haptics.notification(.error)
        }
        purchasing = false
    }

    @MainActor private func handlePurchaseComplete() async {
        guard let token = Keychain.userToken,
              let pi = buySheet else { return }
        // Extract PI id from the PaymentSheet config — Stripe stores it in the client secret
        let piId = String(pi.configuration.merchantDisplayName) // placeholder; use stored PI id
        try? await APIClient.shared.confirmAkenePurchase(paymentIntentId: piId, token: token)
        Haptics.impact(.medium)
        await load()
    }

    @MainActor private func respond(_ id: Int, accept: Bool) async {
        guard let token = Keychain.userToken else { return }
        do {
            if accept {
                try await APIClient.shared.acceptAkeneInvitation(id: id, token: token)
            } else {
                try await APIClient.shared.declineAkeneInvitation(id: id, token: token)
            }
            Haptics.impact(.light)
            await load()
        } catch {
            Haptics.notification(.error)
        }
    }

    // MARK: - Helpers

    private func tabButton(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(label)
                    .font(.mono(11, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? c.text : c.muted)
                Rectangle()
                    .fill(selected ? c.text : Color.clear)
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}
