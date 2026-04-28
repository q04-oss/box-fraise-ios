import SwiftUI
import StripePaymentSheet
import EventKit

// MARK: - Main panel

struct AkenePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    @State private var profile: AkeneProfile?
    @State private var leaderboard: [AkeneLeaderboardEntry] = []
    @State private var invitations: [AkeneInvitation] = []
    @State private var loadState: ViewState<Void> = .idle
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
    @State private var showStaffEvents = false
    @State private var purchases: [AkenePurchaseRecord] = []
    @State private var celebrationProfile: AkeneProfile?

    enum Tab { case rank, invitations }

    private var pendingCount: Int { invitations.filter { $0.isPending }.count }
    private var upcomingInvitations: [AkeneInvitation] {
        invitations.filter { !$0.isCompleted }
    }
    private var pastInvitations: [AkeneInvitation] {
        invitations.filter { $0.isCompleted && $0.isAccepted }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.navigate(to: .profile) }
                Spacer()
                Text("akène")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                HStack(spacing: 16) {
                    if state.user?.isShop ?? false {
                        Button { showStaffEvents = true } label: {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 13)).foregroundStyle(c.muted)
                        }
                        .contentShape(Rectangle())
                        Button { showCreateEvent = true } label: {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 13)).foregroundStyle(c.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    Button { showBuyQuantityPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                            Text("buy").font(.mono(11))
                        }
                        .foregroundStyle(purchasing ? c.muted.opacity(0.4) : c.muted)
                    }
                    .disabled(purchasing)
                    .accessibilityLabel("buy akène")
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // Rank card — tap akène count for purchase history
            if let p = profile {
                rankCard(p)
            } else if loading {
                RoundedRectangle(cornerRadius: Radius.card).fill(c.card).frame(height: 96)
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
            EventDetailSheet(invitation: inv, myUserId: state.user?.id ?? 0) {
                selectedInvitation = nil
                Task { await load() }
            }
            .environment(state).fraiseTheme()
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedHolder) { holder in
            HolderProfileSheet(holder: holder)
                .environment(state).fraiseTheme()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCreateEvent) {
            CreateEventSheet { await load() }
                .environment(state).fraiseTheme()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showStaffEvents) {
            StaffEventsSheet()
                .environment(state).fraiseTheme()
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $celebrationProfile) { p in
            PurchaseCelebrationSheet(profile: p, quantity: buyQuantity)
                .environment(state).fraiseTheme()
                .presentationDragIndicator(.visible)
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
        let delta = state.prevAkeneRank > 0 && (p.rankPosition ?? 0) > 0
            ? state.prevAkeneRank - (p.rankPosition ?? state.prevAkeneRank) : 0

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
                                .foregroundStyle(delta > 0 ? Color.fraiseGreen : Color.fraiseRed)
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
        .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
    }

    // MARK: - Leaderboard

    private var leaderboardList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loadState.isLoading && leaderboard.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        FraiseSkeletonRow(wide: false)
                            .padding(.horizontal, Spacing.md).padding(.vertical, 10)
                        Divider().foregroundStyle(c.border).opacity(0.4).padding(.leading, Spacing.md)
                    }
                } else if case .failed(let msg) = loadState {
                    FraiseErrorView(message: msg) { await load() }.padding(.top, 60)
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

                    // Purchase history at the bottom of the leaderboard
                    if !purchases.isEmpty {
                        Divider().foregroundStyle(c.border).opacity(0.6)
                            .padding(.top, Spacing.sm)
                        Text("your purchases")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(1)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
                        ForEach(purchases) { p in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(p.quantity) \(p.quantity == 1 ? "akène" : "akènes")")
                                        .font(.mono(13)).foregroundStyle(c.text)
                                    Text(FraiseDateFormatter.long(p.purchasedAt))
                                        .font(.mono(9)).foregroundStyle(c.muted)
                                }
                                Spacer()
                                Text("CA$\(p.amountCents / 100)")
                                    .font(.mono(12)).foregroundStyle(c.muted)
                            }
                            .padding(.horizontal, Spacing.md).padding(.vertical, 12)
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, Spacing.md)
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
            LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                if invitations.isEmpty && !loadState.isLoading {
                    FraiseEmptyState(icon: "envelope", title: "no evenings yet",
                                     subtitle: "hold akène to receive evening invitations.")
                        .padding(.top, 60)
                } else {
                    // Upcoming
                    if !upcomingInvitations.isEmpty {
                        ForEach(upcomingInvitations) { inv in
                            Button { selectedInvitation = inv } label: {
                                invitationCard(inv)
                            }
                        }
                    }

                    // Past evenings attended
                    if !pastInvitations.isEmpty {
                        Text("past evenings")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(1)
                            .textCase(.uppercase)
                            .padding(.top, Spacing.sm)
                        ForEach(pastInvitations) { inv in
                            Button { selectedInvitation = inv } label: {
                                pastEveningCard(inv)
                            }
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
                    Label(FraiseDateFormatter.long(date), systemImage: "calendar")
                        .font(.mono(9)).foregroundStyle(c.muted)
                } else {
                    Label(inv.isSeated ? "all seats filled · date tba"
                                                      : "date announced when full",
                          systemImage: "calendar.badge.clock")
                        .font(.mono(9))
                        .foregroundStyle(inv.isSeated
                            ? Color.fraiseGreen : c.muted)
                }
                let left = inv.seatsLeft
                Label(left > 0 ? "\(left) seats left" : "full",
                      systemImage: left > 0 ? "person.2" : "checkmark.circle")
                    .font(.mono(9))
                    .foregroundStyle(left <= 0 ? Color.fraiseGreen
                        : left <= 2 ? Color.fraiseRed : c.muted)
                if inv.isPending, let exp = inv.expiresAt {
                    Label(expiryLabel(exp), systemImage: "timer")
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
            inv.isPending ? c.text.opacity(0.25) : c.border, lineWidth: 0.5))
    }

    private func pastEveningCard(_ inv: AkeneInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(c.card)
                    .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(.system(size: 13)).foregroundStyle(c.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.title.lowercased())
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                if let date = inv.eventDate {
                    Text(FraiseDateFormatter.long(date)).font(.mono(9)).foregroundStyle(c.muted)
                } else if let biz = inv.businessName {
                    Text(biz.lowercased()).font(.mono(9)).foregroundStyle(c.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 10)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
    }

    private func statusPill(_ status: String) -> some View {
        let (label, fg, bg): (String, Color, Color) = switch status {
        case "accepted":   ("accepted",   Color.fraiseGreen, Color.fraiseGreen.opacity(0.12))
        case "declined":   ("declined",   c.muted,             c.searchBg)
        case "waitlisted": ("waitlisted", Color.fraiseOrange, Color.fraiseOrange.opacity(0.12))
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
        loadState = .loading
        async let p  = try? await APIClient.shared.fetchAkeneProfile(token: token)
        async let lb = try? await APIClient.shared.fetchAkeneLeaderboard(token: token)
        async let iv = try? await APIClient.shared.fetchAkeneInvitations(token: token)
        async let pu = try? await APIClient.shared.fetchAkenePurchases(token: token)
        if let v = await pu { purchases = v }
        if let v = await p {
            if let pos = v.rankPosition, state.prevAkeneRank == 0 { state.prevAkeneRank = pos }
            profile = v
            if let pos = v.rankPosition { state.prevAkeneRank = pos }
        }
        if let v = await lb { leaderboard = v }
        if let v = await iv { invitations = v }
        loadState = .loaded(())
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
        await load()
        Haptics.impact(.medium)
        celebrationProfile = profile  // trigger celebration sheet
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


    private func expiryLabel(_ iso: String) -> String {
        guard let date = FraiseDateFormatter.date(from: iso) else { return "" }
        let hours = Int(date.timeIntervalSinceNow / 3600)
        if hours <= 0 { return "expired" }
        return hours < 24 ? "\(hours)h left" : "\(hours / 24)d left"
    }
}

// MARK: - Event detail sheet

private struct EventDetailSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let invitation: AkeneInvitation
    let myUserId: Int
    let onRespond: () async -> Void

    @State private var detail: AkeneEventDetail?
    @State private var attendees: [AkeneAttendee] = []
    @State private var loading = false
    @State private var responding = false
    @State private var calendarAdded = false

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
                                Label(FraiseDateFormatter.long(date), systemImage: "calendar")
                                    .font(.mono(10)).foregroundStyle(c.muted)
                            } else {
                                let st = detail?.status ?? invitation.eventStatus
                                Label(st == "seated" ? "all seats filled · date tba"
                                                     : "date announced when full",
                                      systemImage: "calendar.badge.clock")
                                    .font(.mono(10))
                                    .foregroundStyle(st == "seated"
                                        ? Color.fraiseGreen : c.muted)
                            }
                            let left = detail?.seatsLeft ?? invitation.seatsLeft
                            Label("\(left) of \(invitation.capacity) seats left",
                                  systemImage: left > 0 ? "person.2" : "checkmark.circle")
                                .font(.mono(10))
                                .foregroundStyle(left <= 0 ? Color.fraiseGreen
                                    : left <= 2 ? Color.fraiseRed : c.muted)
                        }

                        // Add to calendar — only when date is confirmed
                        if invitation.eventStatus == "confirmed", let dateStr = invitation.eventDate {
                            Button {
                                addToCalendar(isoDate: dateStr, title: invitation.title)
                            } label: {
                                Label(calendarAdded ? "added to calendar" : "add to calendar",
                                      systemImage: calendarAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                                    .font(.mono(11))
                                    .foregroundStyle(calendarAdded ? Color.fraiseGreen : c.text)
                            }
                            .disabled(calendarAdded)
                            .padding(.top, 4)
                        }
                    }

                    // Who's coming
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("attending")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(1)
                            .textCase(.uppercase)
                        if loading {
                            ForEach(0..<3, id: \.self) { _ in FraiseSkeletonRow(wide: false) }
                        } else if attendees.isEmpty {
                            Text("no one has accepted yet — be the first.")
                                .font(.mono(11)).foregroundStyle(c.muted)
                        } else {
                            ForEach(attendees) { a in
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(a.rankPosition <= 3 ? c.text : c.card)
                                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                                            .frame(width: 32, height: 32)
                                        Text("\(a.rankPosition)")
                                            .font(.mono(9, weight: .medium))
                                            .foregroundStyle(a.rankPosition <= 3 ? c.background : c.muted)
                                    }
                                    Text(a.displayName?.lowercased() ?? "member")
                                        .font(.mono(12)).foregroundStyle(c.text)
                                    Spacer()
                                    Text("\(a.akeneHeld) akène")
                                        .font(.mono(9)).foregroundStyle(c.muted)
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.md)
            }

            // Response buttons
            if invitation.isPending {
                Divider().foregroundStyle(c.border).opacity(0.6)
                HStack(spacing: Spacing.sm) {
                    Button { Task { await respond(accept: false) } } label: {
                        Text("decline")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.searchBg)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    }
                    Button { Task { await respond(accept: true) } } label: {
                        let full = detail?.isFull ?? invitation.isFull
                        Text(full ? "join waitlist" : "accept")
                            .font(.mono(12, weight: .medium)).foregroundStyle(c.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.text)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.button))
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
                _ = try await APIClient.shared.acceptAkeneInvitation(id: invitation.id, token: token)
            } else {
                try await APIClient.shared.declineAkeneInvitation(id: invitation.id, token: token)
            }
            Haptics.impact(accept ? .medium : .light)
            await onRespond()
            dismiss()
        } catch { Haptics.notification(.error) }
        responding = false
    }

    private func addToCalendar(isoDate: String, title: String) {
        guard let date = FraiseDateFormatter.date(from: isoDate) else { return }
        let store = EKEventStore()
        store.requestAccess(to: .event) { granted, _ in
            guard granted else { return }
            let ev = EKEvent(eventStore: store)
            ev.title     = title
            ev.startDate = date
            ev.endDate   = date.addingTimeInterval(3 * 3600)
            ev.calendar  = store.defaultCalendarForNewEvents
            try? store.save(ev, span: .thisEvent, commit: true)
            Task { @MainActor in calendarAdded = true }
        }
    }

}

// MARK: - Holder profile sheet

private struct HolderProfileSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let holder: AkeneLeaderboardEntry

    @State private var profile: AkeneHolderProfile?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("close") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            VStack(spacing: Spacing.lg) {
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
                .padding(.horizontal, Spacing.md)
            }
            .padding(.top, Spacing.lg)
            Spacer()
        }
        .background(c.background.ignoresSafeArea())
        .task {
            guard let token = Keychain.userToken else { return }
            profile = try? await APIClient.shared.fetchAkeneHolderProfile(userId: holder.id, token: token)
        }
    }

    private func statCell(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, design: .serif)).foregroundStyle(c.text)
            Text(label).font(.mono(9)).foregroundStyle(c.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Spacing.md)
    }
}

// MARK: - Staff events sheet

private struct StaffEventsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss

    @State private var events: [AkeneMyEvent] = []
    @State private var loading = false
    @State private var expandedEventId: Int?
    @State private var pickedDate = Date().addingTimeInterval(7 * 86400)
    @State private var settingDate = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("close") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text("your evenings").font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if events.isEmpty && !loading {
                FraiseEmptyState(icon: "calendar", title: "no evenings",
                                 subtitle: "create one with the + button.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .background(c.background.ignoresSafeArea())
        .task { await loadEvents() }
    }

    private func eventRow(_ event: AkeneMyEvent) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text(event.title.lowercased())
                    .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                Spacer()
                statusBadge(event.status)
            }
            HStack(spacing: 12) {
                Label("\(event.acceptedCount)/\(event.capacity) seats",
                      systemImage: "person.2")
                    .font(.mono(10))
                    .foregroundStyle(event.acceptedCount >= event.capacity
                        ? Color.fraiseGreen : c.muted)
                if let date = event.eventDate {
                    Label(FraiseDateFormatter.long(date), systemImage: "calendar")
                        .font(.mono(10)).foregroundStyle(c.muted)
                }
                if let wl = event.waitlistCount, wl > 0 {
                    Label("\(wl) waitlisted", systemImage: "clock")
                        .font(.mono(10)).foregroundStyle(Color.fraiseOrange)
                }
            }
            // Inline date setter for seated events
            if event.isSeated {
                if expandedEventId == event.id {
                    VStack(spacing: Spacing.sm) {
                        DatePicker("", selection: $pickedDate, in: Date()...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        HStack {
                            Button("cancel") {
                                expandedEventId = nil
                            }
                            .font(.mono(12)).foregroundStyle(c.muted)
                            Spacer()
                            Button("confirm date") {
                                Task { await confirmDate(event: event) }
                            }
                            .font(.mono(12, weight: .medium)).foregroundStyle(c.text)
                            .disabled(settingDate)
                        }
                    }
                    .padding(.top, Spacing.sm)
                } else {
                    Button { expandedEventId = event.id } label: {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 12))
                            Text("set the date")
                                .font(.mono(12, weight: .medium))
                        }
                        .foregroundStyle(c.background)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(c.text)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(
            event.isSeated ? c.text.opacity(0.3) : c.border, lineWidth: 0.5))
    }

    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = switch status {
        case "seated":    ("all seats filled", Color.fraiseGreen)
        case "confirmed": ("confirmed",         Color.fraiseBlue)
        case "completed": ("completed",         c.muted)
        default:          ("inviting",          c.muted)
        }
        return Text(label)
            .font(.mono(8)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12)).clipShape(Capsule())
    }

    @MainActor private func confirmDate(event: AkeneMyEvent) async {
        guard let token = Keychain.userToken else { return }
        settingDate = true
        let iso = ISO8601DateFormatter().string(from: pickedDate)
        try? await APIClient.shared.setAkeneEventDate(eventId: event.id, eventDate: iso, token: token)
        expandedEventId = nil
        Haptics.impact(.medium)
        await loadEvents()
        settingDate = false
    }

    @MainActor private func loadEvents() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        events = (try? await APIClient.shared.fetchAkeneMyEvents(token: token)) ?? []
        loading = false
    }

}


// MARK: - Purchase celebration sheet

private struct PurchaseCelebrationSheet: View {
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let profile: AkeneProfile
    let quantity: Int

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: 8) {
                Text("\(profile.akeneHeld)")
                    .font(.system(size: 72, design: .serif, weight: .light))
                    .foregroundStyle(c.text)
                Text(profile.akeneHeld == 1 ? "akène" : "akènes")
                    .font(.mono(14)).foregroundStyle(c.muted)
            }

            if let pos = profile.rankPosition, let total = profile.totalHolders {
                Text("#\(pos) of \(total)")
                    .font(.system(size: 18, design: .serif)).foregroundStyle(c.text)
            }

            Text("your stake in the collectif.")
                .font(.mono(11)).foregroundStyle(c.muted)

            Spacer()

            Button { dismiss() } label: {
                Text("done")
                    .font(.mono(13, weight: .medium)).foregroundStyle(c.background)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(c.text)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            }
            .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.lg)
        }
        .background(c.background.ignoresSafeArea())
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
                    .font(.mono(12, weight: .medium))
                    .foregroundStyle(title.isEmpty ? c.muted : c.text)
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
                    stepperRow("capacity", value: $capacity, range: 4...40)
                    stepperRow("invitations to send", value: $inviteCount,
                               range: capacity...(capacity * 4))
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
                eventDate: nil, capacity: capacity, businessId: nil, token: token)
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
                TextField(placeholder, text: text, axis: .vertical).lineLimit(3...6)
                    .font(.mono(13)).foregroundStyle(c.text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(12).background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(c.border, lineWidth: 0.5))
            } else {
                TextField(placeholder, text: text)
                    .font(.mono(13)).foregroundStyle(c.text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .padding(12).background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.field))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(c.border, lineWidth: 0.5))
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
        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
        .overlay(RoundedRectangle(cornerRadius: Radius.button).strokeBorder(c.border, lineWidth: 0.5))
    }
}
