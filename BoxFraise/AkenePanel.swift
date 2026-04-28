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
    @State private var pendingPaymentIntentId: String?
    @State private var buyQuantity = 1
    @State private var showBuyQuantityPicker = false
    @State private var showBuySheet = false
    @State private var purchasing = false

    enum Tab { case rank, invitations }

    private var pendingCount: Int { invitations.filter { $0.isPending }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                Text("akène")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Button { showBuyQuantityPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                        Text("buy")
                            .font(.mono(11))
                    }
                    .foregroundStyle(purchasing ? c.muted.opacity(0.4) : c.muted)
                }
                .disabled(purchasing)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // My rank card
            if let p = profile {
                rankCard(p)
            } else if loading {
                RoundedRectangle(cornerRadius: 14)
                    .fill(c.card).frame(height: 90)
                    .padding(.horizontal, Spacing.md)
            }

            // Tab bar — always visible
            HStack(spacing: 0) {
                tabButton("leaderboard", badge: 0, selected: tab == .rank) { tab = .rank }
                tabButton("evenings", badge: pendingCount, selected: tab == .invitations) {
                    tab = .invitations
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
        .confirmationDialog("how many?", isPresented: $showBuyQuantityPicker) {
            ForEach([1, 2, 3, 5], id: \.self) { qty in
                Button("\(qty) akène · CA$\(qty * 120)") {
                    buyQuantity = qty
                    guard let token = Keychain.userToken else { return }
                    Task { await preparePurchase(token: token) }
                }
            }
            Button("cancel", role: .cancel) {}
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
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(p.akeneHeld)")
                        .font(.system(size: 32, design: .serif)).foregroundStyle(c.text)
                    Text(p.akeneHeld == 1 ? "akène" : "akènes")
                        .font(.mono(11)).foregroundStyle(c.muted)
                }
                if p.eventsAttended > 0 {
                    Text("\(p.eventsAttended) \(p.eventsAttended == 1 ? "evening" : "evenings") attended")
                        .font(.mono(9)).foregroundStyle(c.muted)
                } else if p.akeneHeld == 0 {
                    Text("buy akène to appear on the leaderboard")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let pos = p.rankPosition, p.akeneHeld > 0 {
                    Text("#\(pos)")
                        .font(.system(size: 32, design: .serif)).foregroundStyle(c.text)
                    if let total = p.totalHolders {
                        Text("of \(total)")
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
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
                if loading && leaderboard.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        FraiseSkeletonRow(wide: false).padding(.horizontal, Spacing.md).padding(.vertical, 10)
                        Divider().foregroundStyle(c.border).opacity(0.4).padding(.leading, Spacing.md)
                    }
                } else if leaderboard.isEmpty {
                    FraiseEmptyState(icon: "chart.bar", title: "no holders yet",
                                     subtitle: "be the first to hold akène.")
                        .padding(.top, 60)
                } else {
                    ForEach(leaderboard) { entry in
                        leaderboardRow(entry)
                        if entry.rankPosition < leaderboard.count {
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, Spacing.md + 36 + 12)
                        }
                    }
                }
            }
            .padding(.vertical, Spacing.sm)
        }
        .refreshable { await load() }
    }

    private func leaderboardRow(_ entry: AkeneLeaderboardEntry) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.rankPosition <= 3 ? c.text : c.card)
                    .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    .frame(width: 36, height: 36)
                Text("\(entry.rankPosition)")
                    .font(.mono(10, weight: .medium))
                    .foregroundStyle(entry.rankPosition <= 3 ? c.background : c.muted)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName?.lowercased() ?? "member")
                    .font(.mono(13)).foregroundStyle(c.text)
                HStack(spacing: 8) {
                    Text("\(entry.akeneHeld) akène")
                        .font(.mono(9)).foregroundStyle(c.muted)
                    if entry.eventsAttended > 0 {
                        Text("· \(entry.eventsAttended) \(entry.eventsAttended == 1 ? "evening" : "evenings")")
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
                }
            }

            Spacer()

            // Show days of holding rather than a raw score
            Text("\(daysHeld(entry.rankScore, held: entry.akeneHeld))d")
                .font(.mono(10)).foregroundStyle(c.muted)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
    }

    // MARK: - Invitations

    private var invitationsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                if invitations.isEmpty && !loading {
                    FraiseEmptyState(icon: "envelope", title: "no evenings yet",
                                     subtitle: "hold akène to receive evening invitations from businesses.")
                        .padding(.top, 60)
                } else {
                    ForEach(invitations) { inv in
                        invitationCard(inv)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .refreshable { await load() }
    }

    private func invitationCard(_ inv: AkeneInvitation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
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
                Label("\(inv.capacity) seats", systemImage: "person.2")
                    .font(.mono(9)).foregroundStyle(c.muted)
            }

            if inv.isPending {
                HStack(spacing: Spacing.sm) {
                    Button { Task { await respond(inv.id, accept: false) } } label: {
                        Text("decline")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(c.searchBg)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button { Task { await respond(inv.id, accept: true) } } label: {
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
            inv.isPending ? c.text.opacity(0.25) : c.border, lineWidth: 0.5))
    }

    private func statusPill(_ status: String) -> some View {
        let (label, fg, bg): (String, Color, Color) = switch status {
        case "accepted": ("accepted", Color(hex: "4CAF50"), Color(hex: "4CAF50").opacity(0.12))
        case "declined": ("declined", c.muted,             c.searchBg)
        default:         ("invited",  c.background,        c.text)
        }
        return Text(label)
            .font(.mono(8)).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(bg).clipShape(Capsule())
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
            pendingPaymentIntentId = extractPaymentIntentId(resp.clientSecret)
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
              let piId = pendingPaymentIntentId else { return }
        try? await APIClient.shared.confirmAkenePurchase(paymentIntentId: piId, token: token)
        pendingPaymentIntentId = nil
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

    private func tabButton(_ label: String, badge: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(.mono(11, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? c.text : c.muted)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.mono(8)).foregroundStyle(c.background)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(c.text).clipShape(Capsule())
                    }
                }
                Rectangle()
                    .fill(selected ? c.text : Color.clear)
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // rank_score = time_score × multiplier; reverse-engineer avg days held
    private func daysHeld(_ score: Int, held: Int) -> Int {
        guard held > 0 else { return 0 }
        return Int(Double(score) / Double(held))
    }

    // Stripe client secrets are formatted as "pi_xxx_secret_yyy" — extract "pi_xxx"
    private func extractPaymentIntentId(_ clientSecret: String) -> String {
        String(clientSecret.split(separator: "_secret_").first ?? Substring(clientSecret))
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}
