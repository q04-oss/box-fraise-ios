import SwiftUI

struct MessagesPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var threads: [MessageThread] = []
    @State private var loading = false
    @State private var showStatusEditor = false
    @State private var statusDraft = ""
    @State private var selectedThread: MessageThread?
    @State private var showCompose = false
    @State private var dateInvitations: [DateInvitation] = []
    @State private var promotions: [PromotionDelivery] = []
    @State private var memoryRequests: [MemoryRequest] = []
    @State private var selectedMemory: MemoryRequest?
    @State private var selectedDateInvitation: DateInvitation?
    @State private var expandedPromotion: Int?

    private var totalUnread: Int { threads.reduce(0) { $0 + $1.unreadCount } }
    private var hasOffers: Bool {
        !memoryRequests.isEmpty ||
        dateInvitations.contains { $0.isPending } ||
        promotions.contains { $0.isUnread }
    }

    private var dorotkaThread: MessageThread? { threads.first { $0.isDorotkaThread } }
    private var otherThreads: [MessageThread] { threads.filter { !$0.isDorotkaThread } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                HStack(spacing: 6) {
                    Text("messages")
                        .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                    if totalUnread > 0 {
                        Text("\(totalUnread)")
                            .font(.mono(9)).foregroundStyle(c.background)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(c.text).clipShape(Capsule())
                    }
                }
                Spacer()
                HStack(spacing: 14) {
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14)).foregroundStyle(c.muted)
                    }
                    Button { showStatusEditor = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13)).foregroundStyle(c.muted)
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // Status line
            if let status = state.user?.status, !status.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "4CAF50")).frame(width: 7, height: 7)
                    Text(status.lowercased())
                        .font(.mono(11)).foregroundStyle(c.muted)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md).padding(.bottom, 8)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            ScrollView {
                LazyVStack(spacing: 0) {
                    // Offers pinned at top — memory prompts, date invitations, promotions
                    if hasOffers {
                        offersSection
                        if !threads.isEmpty {
                            Divider().foregroundStyle(c.border).opacity(0.6)
                        }
                    }

                    // Thread list
                    if loading && threads.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            FraiseSkeletonRow(wide: true).padding(Spacing.md)
                        }
                    } else {
                        if let d = dorotkaThread {
                            DorotkaRow(thread: d) {
                                selectedThread = d
                                state.panel = .messages
                            }
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, 72)
                        }
                        ForEach(otherThreads) { thread in
                            ThreadRow(thread: thread, myUserId: state.user?.id ?? 0) {
                                selectedThread = thread
                                state.panel = .messages
                            }
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, 72)
                        }
                        if threads.isEmpty && !hasOffers {
                            FraiseEmptyState(
                                icon: "bubble.left.and.bubble.right",
                                title: "no messages",
                                subtitle: "meet someone in person to start a conversation."
                            )
                            .padding(.top, 60)
                        }
                    }
                }
            }
            .refreshable { await load() }
        }
        .sheet(item: $selectedMemory) { mr in
            MemoryPromptSheet(request: mr) { await loadOffers() }
                .environment(state).fraiseTheme()
        }
        .sheet(item: $selectedDateInvitation) { inv in
            DateInvitationSheet(invitation: inv) { await loadOffers() }
                .environment(state).fraiseTheme()
        }
        .sheet(item: $selectedThread) { thread in
            ThreadView(thread: thread)
                .environment(state)
                .fraiseTheme()
        }
        .sheet(isPresented: $showCompose) {
            ComposeSheet(existing: threads) { thread in
                selectedThread = thread
            }
            .environment(state)
            .fraiseTheme()
        }
        .sheet(isPresented: $showStatusEditor) {
            StatusEditorSheet(current: state.user?.status ?? "") { newStatus in
                Task {
                    guard let token = Keychain.userToken else { return }
                    try? await APIClient.shared.updateStatus(newStatus, token: token)
                    await state.refreshUser()
                }
            }
            .environment(state)
            .fraiseTheme()
            .presentationDetents([.medium])
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        async let t  = try? await APIClient.shared.fetchThreads(token: token)
        if let v = await t {
            threads = v
            state.totalUnreadMessages = v.reduce(0) { $0 + $1.unreadCount }
        }
        loading = false
        await loadOffers()
    }

    @MainActor private func loadOffers() async {
        guard let token = Keychain.userToken else { return }
        async let d = try? await APIClient.shared.fetchDateInvitations(token: token)
        async let p = try? await APIClient.shared.fetchPromotions(token: token)
        async let m = try? await APIClient.shared.fetchMemoryRequests(token: token)
        if let v = await d { dateInvitations = v }
        if let v = await p { promotions = v }
        if let v = await m { memoryRequests = v }
    }
}

// MARK: - Thread row

private struct ThreadRow: View {
    @Environment(\.fraiseColors) private var c
    let thread: MessageThread
    let myUserId: Int
    let action: () -> Void

    private var preview: String {
        if let cached = MessageCache.get(thread.lastMessageId ?? -1) { return cached }
        if thread.lastType == "variety"  { return "shared a strawberry" }
        if thread.lastType == "popup"    { return "shared a popup" }
        if thread.lastType == "node"     { return "shared a node" }
        if thread.lastType == "broadcast" { return "broadcast" }
        return "🔒 encrypted"
    }

    private var isUndelivered: Bool {
        thread.lastSenderId == myUserId && thread.unreadCount == 0
        // simplified: show "!" when we sent last and no receipts yet
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle().fill(thread.isBusiness ? c.searchBg : c.card)
                        .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                        .frame(width: 48, height: 48)
                    if thread.isBusiness {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 22)).foregroundStyle(c.muted)
                    } else {
                        Text(thread.name?.prefix(1).uppercased() ?? "·")
                            .font(.system(size: 18, design: .serif)).foregroundStyle(c.text)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(thread.name?.lowercased() ?? thread.userCode ?? "member")
                            .font(.mono(13, weight: thread.unreadCount > 0 ? .medium : .regular))
                            .foregroundStyle(c.text)
                        Spacer()
                        if let at = thread.lastMessageAt {
                            Text(shortTime(at))
                                .font(.mono(9)).foregroundStyle(c.muted)
                        }
                    }
                    HStack(spacing: 4) {
                        if isUndelivered {
                            Text("!")
                                .font(.mono(11, weight: .bold)).foregroundStyle(Color(hex: "C0392B"))
                        }
                        Text(preview)
                            .font(.mono(11)).foregroundStyle(c.muted)
                            .lineLimit(1)
                        Spacer()
                        if thread.unreadCount > 0 {
                            Text("\(thread.unreadCount)")
                                .font(.mono(9)).foregroundStyle(c.background)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(c.text).clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        }
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Offers tab

extension MessagesPanel {
    @ViewBuilder var offersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(memoryRequests) { mr in
                Button { selectedMemory = mr } label: { memoryCard(mr) }
            }
            let pendingDates = dateInvitations.filter { $0.isPending }
            if !pendingDates.isEmpty {
                sectionHeader("dinner invitations")
                ForEach(pendingDates) { inv in
                    Button { selectedDateInvitation = inv } label: { dateCard(inv) }
                }
            }
            let unreadPromos = promotions.filter { $0.isUnread }
            if !unreadPromos.isEmpty {
                sectionHeader("from businesses")
                ForEach(unreadPromos) { promo in
                    promotionCard(promo)
                }
            }
        }
        .padding(Spacing.md)
    }

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.mono(9)).foregroundStyle(c.muted).tracking(1)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Spacing.sm)
    }

    private func memoryCard(_ mr: MemoryRequest) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(c.text).frame(width: 36, height: 36)
                    Image(systemName: "heart").font(.system(size: 14)).foregroundStyle(c.background)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("do you want to remember this?")
                        .font(.mono(12, weight: .medium)).foregroundStyle(c.text)
                    if let name = mr.theirName {
                        Text("your evening with \(name.lowercased())")
                            .font(.mono(10)).foregroundStyle(c.muted)
                    }
                    if let biz = mr.businessName {
                        Text("at \(biz.lowercased())").font(.mono(9)).foregroundStyle(c.muted)
                    }
                }
            }
            Text("tap to respond · if you both say yes, messaging opens between you.")
                .font(.mono(9)).foregroundStyle(c.muted)
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(c.text.opacity(0.25), lineWidth: 0.5))
    }

    private func dateCard(_ inv: DateInvitation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if inv.isUnopened {
                            Text("CA$\(inv.feeCents / 100) to open")
                                .font(.mono(8)).foregroundStyle(c.background)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "4CAF50")).clipShape(Capsule())
                        }
                        if inv.isMatched {
                            Text("matched")
                                .font(.mono(8)).foregroundStyle(Color(hex: "4CAF50"))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "4CAF50").opacity(0.12)).clipShape(Capsule())
                        }
                    }
                    Text(inv.title.lowercased())
                        .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                    if let biz = inv.businessName {
                        Text(biz.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.border)
            }
            HStack(spacing: 12) {
                Label(formatDate(inv.eventDate), systemImage: "calendar")
                    .font(.mono(9)).foregroundStyle(c.muted)
                Label("meal covered", systemImage: "fork.knife")
                    .font(.mono(9)).foregroundStyle(c.muted)
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            inv.isPending && inv.isUnopened ? c.text.opacity(0.2) : c.border, lineWidth: 0.5))
    }

    private func promotionCard(_ promo: PromotionDelivery) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(promo.businessName?.lowercased() ?? "business")
                        .font(.mono(9)).foregroundStyle(c.muted)
                    Text(promo.title.lowercased())
                        .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                }
                Spacer()
                if promo.isUnread {
                    Text("earn CA$\(promo.feeCents / 100)")
                        .font(.mono(8)).foregroundStyle(c.background)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "4CAF50")).clipShape(Capsule())
                }
            }
            if expandedPromotion == promo.id {
                Text(promo.body.lowercased())
                    .font(.mono(11)).foregroundStyle(c.muted).lineSpacing(3)
            } else {
                Text(promo.body.lowercased())
                    .font(.mono(11)).foregroundStyle(c.muted)
                    .lineLimit(2)
                Button {
                    expandedPromotion = promo.id
                    if promo.isUnread {
                        Task {
                            guard let token = Keychain.userToken else { return }
                            try? await APIClient.shared.readPromotion(id: promo.id, token: token)
                            await loadOffers()
                        }
                    }
                } label: {
                    Text(promo.isUnread ? "read and earn CA$\(promo.feeCents / 100)" : "read more")
                        .font(.mono(10)).foregroundStyle(promo.isUnread ? Color(hex: "4CAF50") : c.muted)
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            promo.isUnread ? c.text.opacity(0.15) : c.border, lineWidth: 0.5))
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

// MARK: - Memory prompt sheet

private struct MemoryPromptSheet: View {
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let request: MemoryRequest
    let onRespond: () async -> Void

    @State private var responding = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            VStack(spacing: 12) {
                Text("do you want to remember this?")
                    .font(.system(size: 22, design: .serif)).foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                if let name = request.theirName {
                    Text("your evening with \(name.lowercased())")
                        .font(.mono(12)).foregroundStyle(c.muted)
                }
                if let biz = request.businessName {
                    Text("at \(biz.lowercased())").font(.mono(10)).foregroundStyle(c.muted)
                }
            }
            .padding(.horizontal, Spacing.lg)

            Text("if you both say yes, messaging opens between you. neither of you will know the other's answer until you've both responded.")
                .font(.mono(10)).foregroundStyle(c.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)

            Spacer()

            VStack(spacing: Spacing.sm) {
                Button { Task { await respond(wants: true) } } label: {
                    Text("yes, remember this")
                        .font(.mono(13, weight: .medium)).foregroundStyle(c.background)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(c.text).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Button { Task { await respond(wants: false) } } label: {
                    Text("no thanks")
                        .font(.mono(13)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(c.searchBg).clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.lg)
            .disabled(responding)
        }
        .background(c.background.ignoresSafeArea())
    }

    @MainActor private func respond(wants: Bool) async {
        guard let token = Keychain.userToken else { return }
        responding = true
        try? await APIClient.shared.respondToMemory(id: request.id, wants: wants, token: token)
        Haptics.impact(.medium)
        await onRespond()
        dismiss()
        responding = false
    }
}

// MARK: - Date invitation sheet

private struct DateInvitationSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let invitation: DateInvitation
    let onRespond: () async -> Void

    @State private var responding = false
    @State private var earned = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("close") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text("dinner invitation")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Earned indicator
                    if earned || !invitation.isUnopened {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(Color(hex: "4CAF50"))
                            Text("CA$\(invitation.feeCents / 100) added to your account")
                                .font(.mono(11)).foregroundStyle(Color(hex: "4CAF50"))
                        }
                        .padding(.horizontal, Spacing.md).padding(.top, Spacing.sm)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text(invitation.title.lowercased())
                            .font(.system(size: 22, design: .serif)).foregroundStyle(c.text)
                        if let biz = invitation.businessName {
                            Text(biz.lowercased()).font(.mono(12)).foregroundStyle(c.muted)
                        }
                        if let addr = invitation.businessAddress {
                            Text(addr.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                        }
                        if let desc = invitation.description {
                            Text(desc.lowercased()).font(.mono(13)).foregroundStyle(c.muted)
                                .lineSpacing(3).padding(.top, 4)
                        }
                        Label(formatDate(invitation.eventDate), systemImage: "calendar")
                            .font(.mono(11)).foregroundStyle(c.muted)
                        Label("meal fully covered by the business", systemImage: "fork.knife")
                            .font(.mono(11)).foregroundStyle(c.muted)
                    }
                    .padding(.horizontal, Spacing.md)
                }
                .padding(.vertical, Spacing.md)
            }

            if invitation.isPending {
                Divider().foregroundStyle(c.border).opacity(0.6)
                HStack(spacing: Spacing.sm) {
                    Button { Task { await respond(accept: false) } } label: {
                        Text("decline")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.searchBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button { Task { await respond(accept: true) } } label: {
                        Text("accept")
                            .font(.mono(12, weight: .medium)).foregroundStyle(c.background)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(c.text)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(Spacing.md).disabled(responding)
            } else if invitation.isMatched {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "4CAF50"))
                    Text("you've been matched — see you there.")
                        .font(.mono(11)).foregroundStyle(Color(hex: "4CAF50"))
                }
                .padding(Spacing.md)
            }
        }
        .background(c.background.ignoresSafeArea())
        .task {
            guard invitation.isUnopened, let token = Keychain.userToken else { return }
            try? await APIClient.shared.openDateInvitation(id: invitation.id, token: token)
            earned = true
        }
    }

    @MainActor private func respond(accept: Bool) async {
        guard let token = Keychain.userToken else { return }
        responding = true
        do {
            if accept {
                try await APIClient.shared.acceptDateInvitation(id: invitation.id, token: token)
            } else {
                try await APIClient.shared.declineDateInvitation(id: invitation.id, token: token)
            }
            Haptics.impact(.medium)
            await onRespond()
            dismiss()
        } catch { Haptics.notification(.error) }
        responding = false
    }

    private func formatDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
    }
}

// MARK: - Compose sheet

private struct ComposeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let existing: [MessageThread]
    let onSelect: (MessageThread) -> Void

    @State private var contacts: [FraiseContact] = []
    @State private var search = ""

    private var filtered: [FraiseContact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter { ($0.name ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("cancel") { dismiss() }
                    .font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text("new message")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 50)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.md)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(c.muted)
                TextField("search contacts", text: $search)
                    .font(.mono(13)).foregroundStyle(c.text)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(c.searchBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
            .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.sm)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if contacts.isEmpty {
                FraiseEmptyState(icon: "person.2", title: "no contacts",
                                 subtitle: "meet someone in person first.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { contact in
                            Button {
                                let thread = existing.first { $0.contactId == (contact.contactId ?? contact.id) }
                                    ?? MessageThread(
                                        contactId: contact.contactId ?? contact.id,
                                        name: contact.name,
                                        userCode: contact.userCode,
                                        lastMessageId: nil, lastMessageAt: nil,
                                        lastEncrypted: nil, lastType: nil, lastSenderId: nil,
                                        unreadCount: 0, metAt: contact.metAt,
                                        isShop: nil, isDorotka: nil, contactStatus: nil
                                    )
                                dismiss()
                                onSelect(thread)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(c.card)
                                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                                            .frame(width: 44, height: 44)
                                        Text(contact.name?.prefix(1).uppercased() ?? "·")
                                            .font(.system(size: 16, design: .serif)).foregroundStyle(c.text)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(contact.name?.lowercased() ?? contact.userCode ?? "member")
                                            .font(.mono(13)).foregroundStyle(c.text)
                                        if let met = contact.metAt {
                                            Text("met \(shortDate(met))")
                                                .font(.mono(9)).foregroundStyle(c.muted)
                                        }
                                    }
                                    Spacer()
                                    if existing.contains(where: { $0.contactId == (contact.contactId ?? contact.id) }) {
                                        Image(systemName: "bubble.left.fill")
                                            .font(.system(size: 11)).foregroundStyle(c.muted)
                                    }
                                }
                                .padding(.horizontal, Spacing.md).padding(.vertical, 12)
                            }
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, 68)
                        }
                    }
                }
            }
        }
        .background(c.background.ignoresSafeArea())
        .task {
            guard let token = Keychain.userToken else { return }
            contacts = (try? await APIClient.shared.fetchContacts(token: token)) ?? []
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return date.formatted(.dateTime.month(.wide).day())
    }
}

// MARK: - Dorotka pinned row

private struct DorotkaRow: View {
    @Environment(\.fraiseColors) private var c
    let thread: MessageThread
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.text)
                        .frame(width: 48, height: 48)
                    Text("D")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(c.background)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("dorotka")
                            .font(.mono(13, weight: thread.unreadCount > 0 ? .medium : .regular))
                            .foregroundStyle(c.text)
                        Text("co-op")
                            .font(.mono(8)).foregroundStyle(c.background)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(c.muted).clipShape(Capsule())
                        Spacer()
                        if let at = thread.lastMessageAt {
                            Text(shortTime(at))
                                .font(.mono(9)).foregroundStyle(c.muted)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(thread.lastType == "official" ? "dorotka@fraise.chat" : "🔒 encrypted")
                            .font(.mono(11)).foregroundStyle(c.muted).lineLimit(1)
                        Spacer()
                        if thread.unreadCount > 0 {
                            Text("\(thread.unreadCount)")
                                .font(.mono(9)).foregroundStyle(c.background)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(c.text).clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        }
    }

    private func shortTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        if Calendar.current.isDateInToday(date) { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Status editor

private struct StatusEditorSheet: View {
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let current: String
    let onSave: (String) -> Void
    @State private var draft: String

    init(current: String, onSave: @escaping (String) -> Void) {
        self.current = current
        self.onSave = onSave
        _draft = State(initialValue: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Button("cancel") { dismiss() }.font(.mono(12)).foregroundStyle(c.muted)
                Spacer()
                Text("status").font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Button("save") { onSave(draft); dismiss() }
                    .font(.mono(12, weight: .medium)).foregroundStyle(c.text)
            }
            .padding(.horizontal, Spacing.md).padding(.top, Spacing.md)

            TextField("picking up. at atwater. open.", text: $draft)
                .font(.mono(15)).foregroundStyle(c.text)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(c.searchBg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
                .padding(.horizontal, Spacing.md)

            Text("visible to your contacts.")
                .font(.mono(10)).foregroundStyle(c.muted).padding(.horizontal, Spacing.md)

            Spacer()
        }
        .background(c.background.ignoresSafeArea())
    }
}
