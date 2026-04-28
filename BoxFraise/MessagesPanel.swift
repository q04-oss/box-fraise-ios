import SwiftUI

struct MessagesPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var threads: [MessageThread] = []
    @State private var loading = false
    @State private var showStatusEditor = false
    @State private var statusDraft = ""
    @State private var selectedThread: MessageThread?

    private var totalUnread: Int { threads.reduce(0) { $0 + $1.unreadCount } }

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
                Button { showStatusEditor = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13)).foregroundStyle(c.muted)
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

            if loading && threads.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<5, id: \.self) { _ in FraiseSkeletonRow(wide: true).padding(Spacing.md) }
                    }
                }
            } else if threads.isEmpty {
                FraiseEmptyState(
                    icon: "bubble.left.and.bubble.right",
                    title: "no messages",
                    subtitle: "meet someone in person to start a conversation."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(threads) { thread in
                            ThreadRow(thread: thread, myUserId: state.user?.id ?? 0) {
                                selectedThread = thread
                                state.panel = .messages
                            }
                            Divider().foregroundStyle(c.border).opacity(0.4)
                                .padding(.leading, 72)
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .sheet(item: $selectedThread) { thread in
            ThreadView(thread: thread)
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
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        threads = (try? await APIClient.shared.fetchThreads(token: token)) ?? []
        loading = false
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
