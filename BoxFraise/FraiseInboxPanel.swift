import SwiftUI

struct FraiseInboxPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var messages: [FraiseMessage] = []
    @State private var loading = false
    @State private var expandedId: Int?

    private var unreadCount: Int { messages.filter { !$0.isRead }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                HStack(spacing: 6) {
                    Text("inbox")
                        .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.mono(9)).foregroundStyle(c.background)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(c.text).clipShape(Capsule())
                    }
                }
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if loading && messages.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in FraiseSkeletonRow(wide: true) }
                    }.padding(Spacing.md)
                }
            } else if let email = state.user?.fraiseChatEmail, !email.isEmpty {
                if messages.isEmpty {
                    FraiseEmptyState(
                        icon: "envelope",
                        title: "no messages",
                        subtitle: "messages sent to \(email) will appear here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(messages) { msg in
                                MessageRow(
                                    message: msg,
                                    expanded: expandedId == msg.id
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        expandedId = expandedId == msg.id ? nil : msg.id
                                    }
                                    if !msg.isRead {
                                        markRead(msg)
                                    }
                                } onDelete: {
                                    deleteMessage(msg)
                                }
                                Divider().foregroundStyle(c.border).opacity(0.6)
                            }
                        }
                    }
                    .refreshable { await load() }
                }
            } else {
                FraiseEmptyState(
                    icon: "at",
                    title: "no fraise identity yet",
                    subtitle: "verify your first pickup to receive your @fraise.chat address."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        messages = (try? await APIClient.shared.fetchFraiseMessages(token: token)) ?? []
        loading = false
    }

    private func markRead(_ msg: FraiseMessage) {
        guard let token = Keychain.userToken else { return }
        messages = messages.map { m in
            m.id == msg.id
                ? FraiseMessage(id: m.id, fromEmail: m.fromEmail, fromName: m.fromName,
                                subject: m.subject, body: m.body, receivedAt: m.receivedAt,
                                readAt: ISO8601DateFormatter().string(from: Date()))
                : m
        }
        Task { try? await APIClient.shared.markMessageRead(id: msg.id, token: token) }
    }

    private func deleteMessage(_ msg: FraiseMessage) {
        guard let token = Keychain.userToken else { return }
        withAnimation { messages.removeAll { $0.id == msg.id } }
        Task { try? await APIClient.shared.deleteMessage(id: msg.id, token: token) }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    @Environment(\.fraiseColors) private var c
    let message: FraiseMessage
    let expanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Circle()
                        .fill(message.isRead ? Color.clear : c.text)
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(message.senderLabel.lowercased())
                                .font(.mono(13, weight: message.isRead ? .regular : .medium))
                                .foregroundStyle(c.text)
                                .lineLimit(1)
                            Spacer()
                            Text(shortDate(message.receivedAt))
                                .font(.mono(10)).foregroundStyle(c.muted)
                        }
                        if let subject = message.subject, !subject.isEmpty {
                            Text(subject.lowercased())
                                .font(.mono(12)).foregroundStyle(c.muted).lineLimit(1)
                        }
                        if !expanded {
                            Text(message.body)
                                .font(.mono(11)).foregroundStyle(c.muted)
                                .lineLimit(2).lineSpacing(2)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
            }

            if expanded {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(message.body)
                        .font(.mono(12)).foregroundStyle(c.text).lineSpacing(4)

                    Button {
                        Haptics.impact(.light)
                        onDelete()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 11)).foregroundStyle(Color.fraiseRed)
                            Text("delete")
                                .font(.mono(11)).foregroundStyle(Color.fraiseRed)
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(c.card)
            }
        }
    }

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
