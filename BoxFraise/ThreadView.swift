import SwiftUI

struct ThreadView: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss
    let thread: MessageThread

    @State private var messages: [PlatformMessage] = []
    @State private var decrypted: [Int: String] = [:]
    @State private var draft = ""
    @State private var bundle: UserKeyBundle?
    @State private var loading = false
    @State private var sending = false
    @State private var theyAreTyping = false
    @State private var showAttach = false
    @State private var attachedObject: FraiseObject?
    @State private var typingTask: Task<Void, Never>?
    @State private var pollingTask: Task<Void, Never>?

    private var myId: Int { state.user?.id ?? 0 }
    private var contactCode: String { thread.userCode ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(c.muted)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if thread.isBusiness {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(c.muted)
                        }
                        Text(thread.name?.lowercased() ?? contactCode)
                            .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                    }
                    if let met = thread.metAt {
                        Text(thread.isBusiness
                             ? "collected here · \(shortDate(met))"
                             : "met \(shortDate(met))")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(0.3)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 12)

            Divider().foregroundStyle(c.border).opacity(0.6)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(messages) { msg in
                            MessageBubble(
                                message: msg,
                                plaintext: decrypted[msg.id],
                                isMe: msg.senderId == myId
                            )
                            .id(msg.id)
                        }
                        if theyAreTyping {
                            TypingIndicator()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.md).padding(.vertical, 4)
                                .id("typing")
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: theyAreTyping) { _, typing in
                    if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }

            // Attached fraise object preview
            if let obj = attachedObject {
                HStack(spacing: 8) {
                    Image(systemName: fraisObjectIcon(obj.type))
                        .font(.system(size: 11)).foregroundStyle(c.muted)
                    Text(obj.name?.lowercased() ?? obj.type)
                        .font(.mono(11)).foregroundStyle(c.text).lineLimit(1)
                    Spacer()
                    Button { attachedObject = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13)).foregroundStyle(c.muted)
                    }
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 8)
                .background(c.searchBg)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            // Compose bar
            HStack(spacing: 10) {
                Button { showAttach = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16)).foregroundStyle(c.muted)
                        .frame(width: 36, height: 36)
                }

                TextField("message", text: $draft, axis: .vertical)
                    .font(.mono(14)).foregroundStyle(c.text)
                    .lineLimit(1...5)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onChange(of: draft) { _, _ in broadcastTyping() }

                Button {
                    guard !draft.trimmingCharacters(in: .whitespaces).isEmpty || attachedObject != nil else { return }
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(draft.isEmpty && attachedObject == nil ? c.border : c.text)
                }
                .disabled(sending)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 10)
        }
        .task { await load() }
        .onAppear { startPolling() }
        .onDisappear { pollingTask?.cancel(); typingTask?.cancel() }
        .confirmationDialog("share", isPresented: $showAttach) {
            ForEach(state.varieties.prefix(5)) { v in
                Button(v.name) { attachedObject = FraiseObject(type: "variety", id: v.id, name: v.name, detail: v.description, priceCents: v.priceCents) }
            }
            ForEach(state.popups.prefix(3)) { p in
                Button(p.title) { attachedObject = FraiseObject(type: "popup", id: p.id, name: p.title, detail: nil, priceCents: p.priceCents) }
            }
            if let loc = state.nearestCollection {
                Button("share \(loc.name)") { attachedObject = FraiseObject(type: "node", id: loc.id, name: loc.name, detail: loc.neighbourhood, priceCents: nil) }
            }
            Button("cancel", role: .cancel) {}
        }
    }

    // MARK: - Load

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true

        // Fetch key bundle if no session
        if !MessagingKeyStore.hasSession(for: thread.contactId) {
            bundle = try? await APIClient.shared.fetchKeyBundleByCode(contactCode, token: token)
        }

        let fetched = (try? await APIClient.shared.fetchThread(userCode: contactCode, token: token)) ?? []
        messages = fetched
        decryptAll(messages)

        try? await APIClient.shared.markThreadDelivered(userCode: contactCode, token: token)
        try? await APIClient.shared.markThreadRead(userCode: contactCode, token: token)
        loading = false
    }

    private func decryptAll(_ msgs: [PlatformMessage]) {
        for msg in msgs {
            guard msg.senderId != myId else { continue }
            if let cached = MessageCache.get(msg.id) {
                decrypted[msg.id] = cached; continue
            }
            if let text = try? FraiseMessaging.shared.decrypt(message: msg) {
                decrypted[msg.id] = text
            } else {
                decrypted[msg.id] = "[encrypted]"
            }
        }
    }

    // MARK: - Send

    @MainActor private func send() async {
        guard let token = Keychain.userToken else { return }
        let text = draft.trimmingCharacters(in: .whitespaces)
        draft = ""; sending = true

        do {
            let b = bundle ?? (try? await APIClient.shared.fetchKeyBundleByCode(contactCode, token: token))
            guard let b else { sending = false; return }
            bundle = b

            let (wire, x3dhKey, _) = try FraiseMessaging.shared.encrypt(
                plaintext: text.isEmpty ? "(fraise object)" : text,
                forUserId: thread.contactId,
                bundle: b
            )

            let bankDays = state.socialAccess?.bankDays
            let msg = try await APIClient.shared.sendMessage(
                recipientCode: contactCode,
                encryptedBody: wire,
                messageType: attachedObject?.type ?? "text",
                fraiseObject: attachedObject,
                x3dhSenderKey: x3dhKey,
                expiresInDays: bankDays,
                token: token
            )
            decrypted[msg.id] = text.isEmpty ? nil : text
            messages.append(msg)
            attachedObject = nil
            Haptics.impact(.light)
        } catch {
            Haptics.notification(.error)
        }
        sending = false
    }

    // MARK: - Typing

    private func broadcastTyping() {
        typingTask?.cancel()
        typingTask = Task {
            guard let token = Keychain.userToken, !draft.isEmpty else { return }
            try? await APIClient.shared.sendTyping(toUserCode: contactCode, token: token)
        }
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let token = Keychain.userToken else { continue }
                let typing = (try? await APIClient.shared.checkTyping(fromUserCode: contactCode, token: token)) ?? false
                await MainActor.run { theyAreTyping = typing }
            }
        }
    }

    // MARK: - Helpers

    private func shortDate(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return date.formatted(.dateTime.month(.wide).day())
    }

    private func fraisObjectIcon(_ type: String) -> String {
        switch type {
        case "variety":  return "leaf"
        case "popup":    return "calendar.badge.clock"
        case "node":     return "mappin"
        default:         return "square.grid.2x2"
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    @Environment(\.fraiseColors) private var c
    let message: PlatformMessage
    let plaintext: String?
    let isMe: Bool

    private var receiptLabel: String? {
        guard isMe else { return nil }
        if message.readAt != nil      { return "R" }
        if message.deliveredAt != nil { return "D" }
        return "·"
    }

    private var receiptColor: Color {
        message.readAt != nil ? c.text : c.border
    }

    private var expiryLabel: String? {
        guard let exp = message.expiresAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: exp) ?? ISO8601DateFormatter().date(from: exp) else { return nil }
        let days = Int(date.timeIntervalSinceNow / 86400)
        return days > 0 ? "expires in \(days)d" : nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                if let obj = message.fraiseObject {
                    FraiseObjectCard(object: obj, isMe: isMe)
                } else {
                    Text(plaintext ?? "[encrypted]")
                        .font(.mono(13)).foregroundStyle(isMe ? Color.white : c.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMe ? c.text : c.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16,
                            style: .continuous))
                        .overlay(isMe ? nil :
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(c.border, lineWidth: 0.5))
                }

                HStack(spacing: 4) {
                    if let expiry = expiryLabel {
                        Image(systemName: "clock").font(.system(size: 8)).foregroundStyle(c.muted)
                        Text(expiry).font(.mono(8)).foregroundStyle(c.muted)
                    }
                    if let receipt = receiptLabel {
                        Text(receipt).font(.mono(9, weight: .medium)).foregroundStyle(receiptColor)
                    }
                }
            }

            if !isMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 2)
    }
}

// MARK: - Fraise object card

private struct FraiseObjectCard: View {
    @Environment(\.fraiseColors) private var c
    let object: FraiseObject
    let isMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10)).foregroundStyle(c.muted)
                Text(object.type.uppercased())
                    .font(.mono(8)).foregroundStyle(c.muted).tracking(1.5)
            }
            Text(object.name?.lowercased() ?? object.type)
                .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
            if let detail = object.detail {
                Text(detail.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
            }
            if let price = object.priceCents {
                Text(String(format: "CA$%.2f", Double(price) / 100))
                    .font(.mono(11)).foregroundStyle(c.muted)
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        .frame(maxWidth: 220, alignment: .leading)
    }

    private var icon: String {
        switch object.type {
        case "variety":  return "leaf"
        case "popup":    return "calendar.badge.clock"
        case "node":     return "mappin"
        default:         return "square.grid.2x2"
        }
    }
}

// MARK: - Typing indicator

private struct TypingIndicator: View {
    @Environment(\.fraiseColors) private var c
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(c.muted)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: phase)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.border, lineWidth: 0.5))
        .onAppear { phase = true }
    }
}
