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
    @State private var replyTo: PlatformMessage?
    @State private var replyToText: String?
    @AppStorage(AppStorageKey.disappearDays) private var disappearDaysRaw: String = "{}"

    private var myId: Int { state.user?.id ?? 0 }
    private var contactCode: String { thread.userCode ?? "" }

    // Per-thread disappearing message preference stored as JSON dict in a single AppStorage key
    private var disappearDays: Int? {
        guard let data = disappearDaysRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return nil }
        return dict["\(thread.contactId)"]
    }

    private func setDisappearDays(_ days: Int?) {
        var dict = (try? JSONDecoder().decode([String: Int].self,
                    from: disappearDaysRaw.data(using: .utf8) ?? Data())) ?? [:]
        if let days { dict["\(thread.contactId)"] = days }
        else { dict.removeValue(forKey: "\(thread.contactId)") }
        disappearDaysRaw = (try? String(data: JSONEncoder().encode(dict), encoding: .utf8)) ?? "{}"
    }

    private var disappearLabel: String {
        switch disappearDays {
        case 7:  return "7d"
        case 30: return "30d"
        default: return "∞"
        }
    }

    private func cycleDisappear() {
        switch disappearDays {
        case nil: setDisappearDays(7)
        case 7:   setDisappearDays(30)
        default:  setDisappearDays(nil)
        }
        Haptics.impact(.light)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(c.muted)
                }
                .contentShape(Rectangle()).accessibilityLabel("back")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if thread.isBusiness {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(c.muted)
                        }
                        Text(thread.name?.lowercased() ?? contactCode)
                            .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                    }
                    // Contact status takes priority over met date
                    if let status = thread.contactStatus, !status.isEmpty {
                        Text(status.lowercased())
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(0.3)
                    } else if let met = thread.metAt {
                        Text(thread.isBusiness
                             ? "collected here · \(FraiseDateFormatter.medium(met))"
                             : "met \(FraiseDateFormatter.medium(met))")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(0.3)
                    }
                }
                Spacer()
                // Disappearing messages toggle
                Button { cycleDisappear() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: disappearDays != nil ? "timer" : "timer.circle")
                            .font(.system(size: 11))
                        Text(disappearLabel)
                            .font(.mono(9))
                    }
                    .foregroundStyle(disappearDays != nil ? c.text : c.muted)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(disappearDays != nil ? c.searchBg : Color.clear)
                    .clipShape(Capsule())
                }
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
                                isMe: msg.senderId == myId,
                                onReply: {
                                    replyTo = msg
                                    replyToText = msg.senderId == myId ? decrypted[msg.id] : decrypted[msg.id]
                                }
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
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: theyAreTyping) { _, typing in
                    if typing { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                }
            }

        }
        // Compose bar floats above the keyboard via safeAreaInset so the
        // message list scrolls behind it rather than being pushed by it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // Reply-to preview bar
                if let reply = replyTo {
                    HStack(spacing: 8) {
                        Rectangle().fill(c.muted).frame(width: 2).cornerRadius(1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.senderId == myId ? "you" : (thread.name?.lowercased() ?? "them"))
                                .font(.mono(8)).foregroundStyle(c.muted).tracking(0.5)
                            Text(replyToText ?? reply.reply?.snippet ?? "[encrypted]")
                                .font(.mono(11)).foregroundStyle(c.text).lineLimit(2)
                        }
                        Spacer()
                        Button { replyTo = nil; replyToText = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(c.muted)
                        }
                        .accessibilityLabel("clear reply")
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, 8)
                    .background(c.searchBg)
                }

                // Fraise object attachment preview
                if let obj = attachedObject {
                    HStack(spacing: 8) {
                        Image(systemName: fraiseObjectIcon(obj.type))
                            .font(.system(size: 11)).foregroundStyle(c.muted)
                        Text(obj.name?.lowercased() ?? obj.type.rawValue)
                            .font(.mono(11)).foregroundStyle(c.text).lineLimit(1)
                        Spacer()
                        Button { attachedObject = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(c.muted)
                        }
                        .accessibilityLabel("remove attachment")
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, 8)
                    .background(c.searchBg)
                }

                Divider().foregroundStyle(c.border).opacity(Divide.section)

                // Compose bar
                HStack(spacing: 10) {
                    Button { showAttach = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16)).foregroundStyle(c.muted)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("attach")
                    .contentShape(Rectangle())

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
                    .accessibilityLabel("send")
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 10)
                .background(.regularMaterial)
            }
        }
        .task { await load() }
        .onAppear { startPolling() }
        .onDisappear { pollingTask?.cancel(); typingTask?.cancel() }
        .confirmationDialog("share", isPresented: $showAttach) {
            ForEach(state.varieties.prefix(5)) { v in
                Button(v.name) {
                    attachedObject = FraiseObject(type: "variety", id: v.id, name: v.name,
                                                  detail: v.description, priceCents: v.priceCents)
                }
            }
            ForEach(state.popups.prefix(3)) { p in
                Button(p.title) {
                    attachedObject = FraiseObject(type: "popup", id: p.id, name: p.title,
                                                  detail: nil, priceCents: p.priceCents)
                }
            }
            if let loc = state.nearestCollection {
                Button("share \(loc.name)") {
                    attachedObject = FraiseObject(type: "node", id: loc.id, name: loc.name,
                                                  detail: loc.neighbourhood, priceCents: nil)
                }
            }
            Button("cancel", role: .cancel) {}
        }
    }

    // MARK: - Load

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true

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

        // Capture and clear reply state before the async gap
        let replyId     = replyTo?.id
        let replySnip   = replyToText ?? replyTo?.reply?.snippet
        replyTo = nil; replyToText = nil

        do {
            let b = bundle ?? (try? await APIClient.shared.fetchKeyBundleByCode(contactCode, token: token))
            guard let b else { sending = false; return }
            bundle = b

            let (wire, x3dhKey, _) = try FraiseMessaging.shared.encrypt(
                plaintext: text.isEmpty ? "(fraise object)" : text,
                forUserId: thread.contactId,
                bundle: b
            )

            let msg = try await APIClient.shared.sendMessage(
                recipientCode: contactCode,
                encryptedBody: wire,
                messageType: attachedObject?.type ?? "text",
                fraiseObject: attachedObject,
                x3dhSenderKey: x3dhKey,
                expiresInDays: disappearDays,
                replyToId: replyId,
                replyToSnippet: replySnip,
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

    // MARK: - Typing + live polling

    private func broadcastTyping() {
        typingTask?.cancel()
        typingTask = Task {
            guard let token = Keychain.userToken, !draft.isEmpty else { return }
            try? await APIClient.shared.sendTyping(toUserCode: contactCode, token: token)
        }
    }

    private func startPolling() {
        pollingTask = Task {
            // Interval starts at 3 s and backs off to 15 s after 5 quiet rounds,
            // reducing battery drain when the conversation is idle.
            var quietRounds = 0
            while !Task.isCancelled {
                let interval: UInt64 = quietRounds >= 5 ? 15_000_000_000 : 3_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard let token = Keychain.userToken else { continue }

                async let typingResult  = APIClient.shared.checkTyping(fromUserCode: contactCode, token: token)
                async let newMsgsResult = APIClient.shared.fetchNewMessages(
                    userCode: contactCode,
                    afterId: await MainActor.run { messages.last?.id ?? 0 },
                    token: token
                )

                let typing  = (try? await typingResult)  ?? false
                let newMsgs = (try? await newMsgsResult) ?? []

                await MainActor.run {
                    theyAreTyping = typing
                    if !newMsgs.isEmpty {
                        let existing = Set(messages.map { $0.id })
                        let fresh = newMsgs.filter { !existing.contains($0.id) }
                        if !fresh.isEmpty {
                            decryptAll(fresh)
                            messages.append(contentsOf: fresh)
                            Haptics.impact(.light)
                        }
                    }
                }

                if newMsgs.isEmpty && !typing {
                    quietRounds += 1
                } else {
                    quietRounds = 0
                    try? await APIClient.shared.markThreadDelivered(userCode: contactCode, token: token)
                    try? await APIClient.shared.markThreadRead(userCode: contactCode, token: token)
                }
            }
        }
    }

    // MARK: - Helpers

    private func fraiseObjectIcon(_ type: FraiseObjectType) -> String {
        switch type {
        case .variety: return "leaf"
        case .popup:   return "calendar.badge.clock"
        case .node:    return "mappin"
        case .other:   return "square.grid.2x2"
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    @Environment(\.fraiseColors) private var c
    let message: PlatformMessage
    let plaintext: String?
    let isMe: Bool
    let onReply: () -> Void

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
        guard let date = FraiseDateFormatter.date(from: exp) else { return nil }
        let days = Int(date.timeIntervalSinceNow / 86400)
        return days > 0 ? "expires in \(days)d" : nil
    }

    private var timeLabel: String { FraiseDateFormatter.time(message.sentAt) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                // Quoted reply snippet
                if let context = message.reply {
                    HStack(spacing: 5) {
                        Rectangle().fill(c.muted).frame(width: 2).cornerRadius(1)
                        Text(context.snippet)
                            .font(.mono(10)).foregroundStyle(c.muted).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let obj = message.fraiseObject {
                    FraiseObjectCard(object: obj, isMe: isMe)
                } else {
                    Text(plaintext ?? "[encrypted]")
                        .font(.mono(13)).foregroundStyle(isMe ? Color.white : c.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(isMe ? c.text : c.card)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(isMe ? nil :
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(c.border, lineWidth: 0.5))
                }

                HStack(spacing: 4) {
                    Text(timeLabel)
                        .font(.mono(8)).foregroundStyle(c.muted)
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
        .contextMenu {
            Button("reply", systemImage: "arrowshape.turn.up.left") { onReply() }
        }
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
                Text(object.type.rawValue.uppercased())
                    .font(.mono(8)).foregroundStyle(c.muted).tracking(1.5)
            }
            Text(object.name?.lowercased() ?? object.type.rawValue)
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
