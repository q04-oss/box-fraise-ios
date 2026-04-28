import SwiftUI
import StripePaymentSheet

// MARK: - Main panel

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
    @State private var selectedInvitation: AkeneInvitation?
    @State private var selectedHolder: AkeneLeaderboardEntry?
    @State private var showCreateEvent = false
    @State private var showRankShare = false
    @State private var rankShareImage: Image?
    @AppStorage("akene_prev_rank") private var prevRank: Int = 0

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
                HStack(spacing: 14) {
                    if state.user?.isShop == true {
                        Button { showCreateEvent = true } label: {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 14)).foregroundStyle(c.muted)
                        }
                    }
                    Button { showBuyQuantityPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                            Text("buy").font(.mono(11))
                        }
                        .foregroundStyle(purchasing ? c.muted.opacity(0.4) : c.muted)
                    }
                    .disabled(purchasing)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // Rank card
            if let p = profile {
                rankCard(p)
            } else if loading {
                RoundedRectangle(cornerRadius: 14).fill(c.card).frame(height: 96)
                    .padding(.horizontal, Spacing.md)
            }

            // Tabs
            HStack(spacing: 0) {
                tabButton("leaderboard", badge: 0, selected: tab == .rank) { tab = .rank }
                tabButton("evenings", badge: pendingCount, selected: tab == .invitations) {
                    tab = .invitations
                }
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if tab == .rank { leaderboardList } else { invitationsList }
        }
        .sheet(item: $selectedInvitation) { inv in
            EventDetailSheet(invitation: inv, myUserId: state.user?.id ?? 0) { accepted, waitlisted in
                selectedInvitation = nil
                Task { await load() }
            }
            .environment(state).fraiseTheme()
        }
        .sheet(item: $selectedHolder) { holder in
            HolderProfileSheet(holder: holder)
                .environment(state).fraiseTheme()
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventSheet { await load() }
                .environment(state).fraiseTheme()
        }
        .sheet(isPresented: $showRankShare) {
            if let img = rankShareImage {
                ShareLink(item: img, preview: SharePreview("my akène rank", image: img)) {
                    Text("share").font(.mono(13))
                }
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
            if case .completed = result { Task { await handlePurchaseComplete() } }
        }
        .task { await load() }
    }

    // MARK: - Rank card

    private func rankCard(_ p: AkeneProfile) -> some View {
        let delta = prevRank > 0 && (p.rankPosition ?? 0) > 0
            ? prevRank - (p.rankPosition ?? prevRank) : 0

        return HStack(alignment: .top, spacing: 0) {
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
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        if delta != 0 {
                            Text(delta > 0 ? "↑\(delta)" : "↓\(abs(delta))")
                                .font(.mono(9))
                                .foregroundStyle(delta > 0 ? Color(hex: "4CAF50") : Color(hex: "C0392B"))
                        }
                        Text("#\(pos)")
                            .font(.system(size: 32, design: .serif)).foregroundStyle(c.text)
                    }
                    if let total = p.totalHolders {
                        Text("of \(total)").font(.mono(9)).foregroundStyle(c.muted)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
        .onTapGesture {
            if p.akeneHeld > 0 { generateAndShare(p) }
        }
    }

    // MARK: - Leaderboard

    private var leaderboardList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loading && leaderboard.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        FraiseSkeletonRow(wide: false)
                            .padding(.horizontal, Spacing.md).padding(.vertical, 10)
                        Divider().foregroundStyle(c.border).opacity(0.4).padding(.leading, Spacing.md)
                    }
                } else if leaderboard.isEmpty {
                    FraiseEmptyState(icon: "chart.bar", title: "no holders yet",
                                     subtitle: "be the first to hold akène.")
                        .padding(.top, 60)
                } else {
                    ForEach(leaderboard) { entry in
                        Button { selectedHolder = entry } label: {
                            leaderboardRow(entry)
                        }
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
                    Text("\(entry.akeneHeld) akène").font(.mono(9)).foregroundStyle(c.muted)
                    if entry.eventsAttended > 0 {
                        Text("· \(entry.eventsAttended) \(entry.eventsAttended == 1 ? "evening" : "evenings")")
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
                }
            }
            Spacer()
            Text("\(daysHeld(entry.rankScore, held: entry.akeneHeld))d")
                .font(.mono(10)).foregroundStyle(c.muted)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(c.border)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
    }

    // MARK: - Invitations

    private var invitationsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.sm) {
                if invitations.isEmpty && !loading {
                    FraiseEmptyState(icon: "envelope", title: "no evenings yet",
                                     subtitle: "hold akène to receive evening invitations.")
                        .padding(.top, 60)
                } else {
                    ForEach(invitations) { inv in
                        Button { selectedInvitation = inv } label: {
                            invitationCard(inv)
                        }
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
                        Text(biz.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                    }
                }
                Spacer()
                statusPill(inv.status)
            }

            HStack(spacing: 12) {
                if let date = inv.eventDate {
                    Label(formatDate(date), systemImage: "calendar")
                        .font(.mono(9)).foregroundStyle(c.muted)
                } else {
                    Label(inv.eventStatus == "seated" ? "all seats filled · date tba"
                                                      : "date announced when full",
                          systemImage: "calendar.badge.clock")
                        .font(.mono(9))
                        .foregroundStyle(inv.eventStatus == "seated"
                            ? Color(hex: "4CAF50") : c.muted)
                }
                // Seats remaining
                let left = inv.seatsLeft
                Label(left > 0 ? "\(left) seats left" : "full",
                      systemImage: left > 0 ? "person.2" : "person.2.slash")
                    .font(.mono(9))
                    .foregroundStyle(left <= 2 ? Color(hex: "C0392B") : c.muted)
                // Expiry countdown
                if inv.isPending, let exp = inv.expiresAt {
                    Label(expiryLabel(exp), systemImage: "timer")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
            }

            HStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10)).foregroundStyle(c.border)
                Text("tap to see who's coming")
                    .font(.mono(9)).foregroundStyle(c.muted)
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
        case "accepted":   ("accepted",   Color(hex: "4CAF50"), Color(hex: "4CAF50").opacity(0.12))
        case "declined":   ("declined",   c.muted,             c.searchBg)
        case "waitlisted": ("waitlisted", Color(hex: "E67E22"), Color(hex: "E67E22").opacity(0.12))
        default:           ("invited",    c.background,        c.text)
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
        if let v = await p  {
            if let pos = v.rankPosition, prevRank == 0 { prevRank = pos }
            profile = v
            if let pos = v.rankPosition { prevRank = pos }
        }
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
        } catch { Haptics.notification(.error) }
        purchasing = false
    }

    @MainActor private func handlePurchaseComplete() async {
        guard let token = Keychain.userToken, let piId = pendingPaymentIntentId else { return }
        try? await APIClient.shared.confirmAkenePurchase(paymentIntentId: piId, token: token)
        pendingPaymentIntentId = nil
        Haptics.impact(.medium)
        await load()
    }

    private func generateAndShare(_ p: AkeneProfile) {
        let card = RankShareCard(profile: p, name: state.user?.displayName ?? "")
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            rankShareImage = Image(uiImage: uiImage)
            showRankShare = true
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
                Rectangle().fill(selected ? c.text : Color.clear).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func daysHeld(_ score: Int, held: Int) -> Int {
        guard held > 0 else { return 0 }
        return Int(Double(score) / Double(held))
    }

    private func extractPaymentIntentId(_ clientSecret: String) -> String {
        String(clientSecret.split(separator: "_secret_").first ?? Substring(clientSecret))
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private func expiryLabel(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let hours = Int(date.timeIntervalSinceNow / 3600)
        if hours <= 0 { return "expired" }
        if hours < 24 { return "\(hours)h left" }
        return "\(hours / 24)d left"
    }
}

// MARK: - Event detail sheet

private struct EventDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let invitation: AkeneInvitation
    let myUserId: Int
    let onRespond: (Bool, Bool) async -> Void

    @State private var detail: AkeneEventDetail?
    @State private var attendees: [AkeneAttendee] = []
    @State private var loading = false
    @State private var responding = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("close") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text(invitation.title.lowercased())
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Event info
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        if let biz = invitation.businessName {
                            Text(biz.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                        }
                        if let desc = invitation.description {
                            Text(desc.lowercased()).font(.mono(13)).foregroundStyle(c.text)
                        }
                        HStack(spacing: 16) {
                            if let date = invitation.eventDate {
                                Label(formatDate(date), systemImage: "calendar")
                                    .font(.mono(10)).foregroundStyle(c.muted)
                            } else {
                                let st = detail?.status ?? invitation.eventStatus
                                Label(st == "seated" ? "all seats filled · date tba"
                                                     : "date announced when full",
                                      systemImage: "calendar.badge.clock")
                                    .font(.mono(10))
                                    .foregroundStyle(st == "seated"
                                        ? Color(hex: "4CAF50") : c.muted)
                            }
                            let left = detail?.seatsLeft ?? invitation.seatsLeft
                            Label("\(left) of \(invitation.capacity) seats left",
                                  systemImage: left > 0 ? "person.2" : "checkmark.circle")
                                .font(.mono(10))
                                .foregroundStyle(left <= 0 ? Color(hex: "4CAF50")
                                    : left <= 2 ? Color(hex: "C0392B") : c.muted)
                        }
                    }

                    // Who's coming
                    if !attendees.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("attending")
                                .font(.mono(9)).foregroundStyle(c.muted).tracking(1)
                                .textCase(.uppercase)
                            ForEach(attendees) { a in
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(c.card)
                                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                                            .frame(width: 32, height: 32)
                                        Text("\(a.rankPosition)")
                                            .font(.mono(9, weight: .medium)).foregroundStyle(c.muted)
                                    }
                                    Text(a.displayName?.lowercased() ?? "member")
                                        .font(.mono(12)).foregroundStyle(c.text)
                                    Spacer()
                                    Text("\(a.akeneHeld) akène")
                                        .font(.mono(9)).foregroundStyle(c.muted)
                                }
                            }
                        }
                    } else if loading {
                        ForEach(0..<3, id: \.self) { _ in
                            FraiseSkeletonRow(wide: false)
                        }
                    } else {
                        Text("no one has accepted yet.")
                            .font(.mono(11)).foregroundStyle(c.muted)
                    }
                }
                .padding(Spacing.md)
            }

            // Response buttons for pending invitations
            if invitation.isPending {
                Divider().foregroundStyle(c.border).opacity(0.6)
                HStack(spacing: Spacing.sm) {
                    Button {
                        Task { await respond(accept: false) }
                    } label: {
                        Text("decline")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.searchBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        Task { await respond(accept: true) }
                    } label: {
                        let full = detail?.isFull ?? invitation.isFull
                        Text(full ? "join waitlist" : "accept")
                            .font(.mono(12, weight: .medium))
                            .foregroundStyle(c.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(responding)
                }
                .padding(Spacing.md)
            }
        }
        .background(c.background.ignoresSafeArea())
        .task {
            guard let token = Keychain.userToken else { return }
            loading = true
            async let d = try? await APIClient.shared.fetchAkeneEventDetail(id: invitation.eventId, token: token)
            async let a = try? await APIClient.shared.fetchAkeneAttendees(eventId: invitation.eventId, token: token)
            if let v = await d { detail = v }
            if let v = await a { attendees = v }
            loading = false
        }
    }

    @MainActor private func respond(accept: Bool) async {
        guard let token = Keychain.userToken else { return }
        responding = true
        do {
            if accept {
                let waitlisted = try await APIClient.shared.acceptAkeneInvitation(id: invitation.id, token: token)
                Haptics.impact(.medium)
                await onRespond(true, waitlisted)
            } else {
                try await APIClient.shared.declineAkeneInvitation(id: invitation.id, token: token)
                Haptics.impact(.light)
                await onRespond(false, false)
            }
            dismiss()
        } catch { Haptics.notification(.error) }
        responding = false
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.wide).day().year())
    }
}

// MARK: - Holder profile sheet

private struct HolderProfileSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let holder: AkeneLeaderboardEntry

    @State private var profile: AkeneHolderProfile?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("close") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            VStack(spacing: Spacing.lg) {
                // Avatar
                ZStack {
                    Circle().fill(c.card)
                        .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                        .frame(width: 72, height: 72)
                    Text(holder.displayName?.prefix(1).uppercased() ?? "·")
                        .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)
                }

                VStack(spacing: 4) {
                    Text(holder.displayName?.lowercased() ?? "member")
                        .font(.system(size: 20, design: .serif)).foregroundStyle(c.text)
                    Text("#\(holder.rankPosition) on the leaderboard")
                        .font(.mono(10)).foregroundStyle(c.muted)
                }

                // Stats grid
                HStack(spacing: 0) {
                    statCell("\(holder.akeneHeld)", label: "akène")
                    Divider().frame(height: 40).foregroundStyle(c.border)
                    statCell("\(holder.eventsAttended)", label: "evenings")
                    Divider().frame(height: 40).foregroundStyle(c.border)
                    let days = profile.map { p in
                        p.akeneHeld > 0 ? Int(Double(p.rankScore) / Double(p.akeneHeld)) : 0
                    } ?? 0
                    statCell("\(days)d", label: "avg hold")
                }
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                .padding(.horizontal, Spacing.md)
            }
            .padding(.top, Spacing.lg)

            Spacer()
        }
        .background(c.background.ignoresSafeArea())
        .task {
            guard let token = Keychain.userToken else { return }
            loading = true
            profile = try? await APIClient.shared.fetchAkeneHolderProfile(userId: holder.id, token: token)
            loading = false
        }
    }

    private func statCell(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, design: .serif)).foregroundStyle(c.text)
            Text(label).font(.mono(9)).foregroundStyle(c.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Create event sheet (staff only)

private struct CreateEventSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let onCreated: () async -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var capacity = 10
    @State private var inviteCount = 20
    @State private var submitting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("cancel") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text("new evening").font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Button("create") { Task { await submit() } }
                    .font(.mono(12, weight: .medium)).foregroundStyle(title.isEmpty ? c.muted : c.text)
                    .disabled(title.isEmpty || submitting)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    fraiseField("title", text: $title, placeholder: "a winter dinner")
                    fraiseField("description", text: $description,
                                placeholder: "details about the evening", multiline: true)

                    Text("the date is announced after all seats are filled.")
                        .font(.mono(9)).foregroundStyle(c.muted)

                    // Capacity
                    stepperRow("capacity", value: $capacity, range: 4...40)
                    stepperRow("invitations to send", value: $inviteCount, range: capacity...(capacity * 4))
                }
                .padding(Spacing.md)
            }
        }
        .background(c.background.ignoresSafeArea())
    }

    @MainActor private func submit() async {
        guard let token = Keychain.userToken, !title.isEmpty else { return }
        submitting = true
        do {
            let event = try await APIClient.shared.createAkeneEvent(
                title: title,
                description: description.isEmpty ? nil : description,
                eventDate: nil,
                capacity: capacity,
                businessId: nil,
                token: token
            )
            _ = try? await APIClient.shared.sendAkeneInvitations(
                eventId: event.id, count: inviteCount, token: token)
            Haptics.impact(.medium)
            await onCreated()
            dismiss()
        } catch { Haptics.notification(.error) }
        submitting = false
    }

    private func fraiseField(_ label: String, text: Binding<String>,
                              placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.mono(9)).foregroundStyle(c.muted).tracking(1).textCase(.uppercase)
            if multiline {
                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.mono(13)).foregroundStyle(c.text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(12).background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
            } else {
                TextField(placeholder, text: text)
                    .font(.mono(13)).foregroundStyle(c.text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(12).background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
            }
        }
    }

    private func stepperRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label).font(.mono(10)).foregroundStyle(c.muted).tracking(1)
            Spacer()
            Stepper("\(value.wrappedValue)", value: value, in: range)
                .font(.mono(13)).foregroundStyle(c.text)
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
    }
}

// MARK: - Shareable rank card

private struct RankShareCard: View {
    let profile: AkeneProfile
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("box fraise").font(.system(size: 11, design: .serif))
                    .tracking(2).textCase(.uppercase).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("akène").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(profile.akeneHeld)")
                    .font(.system(size: 56, design: .serif, weight: .light)).foregroundStyle(.white)
                Text(profile.akeneHeld == 1 ? "akène" : "akènes")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
            }
            if let pos = profile.rankPosition {
                Text("#\(pos) of \(profile.totalHolders ?? 0)")
                    .font(.system(size: 16, design: .serif)).foregroundStyle(.white.opacity(0.8))
            }
            Text(name.lowercased())
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(28)
        .frame(width: 320, height: 200)
        .background(Color(hex: "1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
