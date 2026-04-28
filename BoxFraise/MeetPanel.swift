import SwiftUI

struct MeetPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var tab: Tab = .meet
    @State private var session = MeetSession()
    @State private var myToken: String?
    @State private var pending: [PendingConnection] = []
    @State private var contacts: [FraiseContact] = []
    @State private var loading = false
    @State private var pulse = false

    enum Tab { case meet, requests, met }

    private var unapprovedCount: Int { pending.filter { !$0.iApproved }.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.panel = .profile; session.stop() }
                Spacer()
                Text("met").font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            // Tabs
            HStack(spacing: 0) {
                tabBtn(.meet, label: "meet")
                tabBtn(.requests, label: unapprovedCount > 0 ? "requests (\(unapprovedCount))" : "requests")
                tabBtn(.met, label: "met\(contacts.isEmpty ? "" : " (\(contacts.count))")")
            }
            .padding(.horizontal, Spacing.md).padding(.bottom, 10)

            Divider().foregroundStyle(c.border).opacity(0.6)

            switch tab {
            case .meet:     meetView
            case .requests: requestsView
            case .met:      metView
            }
        }
        .task { await load() }
        .onAppear { pulse = true }
        .onDisappear { session.stop() }
        .onChange(of: session.state) { _, s in
            if case .found = s { Haptics.notification(.success) }
        }
    }

    // MARK: - Meet tab

    private var meetView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {

                // Proximity ring
                ZStack {
                    ForEach([1.0, 0.7, 0.4], id: \.self) { opacity in
                        Circle()
                            .stroke(c.text.opacity(opacity * ringOpacity), lineWidth: 1)
                            .frame(width: ringSize(opacity), height: ringSize(opacity))
                            .animation(
                                .easeInOut(duration: 2).repeatForever(autoreverses: true)
                                    .delay((1.0 - opacity) * 0.4),
                                value: pulse
                            )
                    }
                    Circle()
                        .fill(c.card)
                        .frame(width: 88, height: 88)
                        .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    Image(systemName: stateIcon)
                        .font(.system(size: 26))
                        .foregroundStyle(stateIconColor)
                        .symbolEffect(.pulse, isActive: session.state == .scanning)
                }
                .frame(height: 200)
                .padding(.top, Spacing.lg)

                // Status text
                VStack(spacing: 6) {
                    Text(stateTitle)
                        .font(.system(size: 22, design: .serif)).foregroundStyle(c.text)
                        .multilineTextAlignment(.center)
                    Text(stateSubtitle)
                        .font(.mono(11)).foregroundStyle(c.muted).lineSpacing(3)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.lg)

                // CTA
                switch session.state {
                case .idle:
                    Button { Task { await startMeet() } } label: {
                        HStack {
                            Text("start").font(.mono(13, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                        .background(c.text).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, Spacing.md)

                case .found(let theirToken):
                    Button { Task { await confirm(theirToken: theirToken) } } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 13)).foregroundStyle(.white)
                            Text("confirm tap")
                                .font(.mono(13, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                        .background(Color.fraiseGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, Spacing.md)

                case .done:
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14)).foregroundStyle(Color.fraiseGreen)
                            Text("request sent · awaiting their approval")
                                .font(.mono(11)).foregroundStyle(Color.fraiseGreen)
                        }
                        Button {
                            session.stop()
                            Task { await startMeet() }
                        } label: {
                            Text("meet someone else")
                                .font(.mono(11)).foregroundStyle(c.muted)
                        }
                    }

                case .error(let msg):
                    VStack(spacing: 10) {
                        Text(msg).font(.mono(11)).foregroundStyle(Color.fraiseRed)
                            .multilineTextAlignment(.center)
                        Button { Task { await startMeet() } } label: {
                            Text("try again").font(.mono(11)).foregroundStyle(c.muted)
                        }
                    }
                    .padding(.horizontal, Spacing.md)

                case .scanning, .starting, .confirming:
                    Button {
                        session.stop()
                        myToken = nil
                    } label: {
                        Text("stop").font(.mono(11)).foregroundStyle(c.muted)
                    }

                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Requests tab

    private var requestsView: some View {
        Group {
            if pending.isEmpty {
                FraiseEmptyState(
                    icon: "person.2",
                    title: "no pending requests",
                    subtitle: "meeting requests will appear here for 48 hours after an in-person tap."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(pending) { conn in
                            PendingCard(connection: conn) {
                                pending.removeAll { $0.id == conn.id }
                                await load()
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
                .refreshable { await load() }
            }
        }
    }

    // MARK: - Met tab

    private var metView: some View {
        Group {
            if contacts.isEmpty {
                FraiseEmptyState(
                    icon: "person.2.circle",
                    title: "no connections yet",
                    subtitle: "hold your phones together with another fraise user to meet them."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(contacts) { contact in
                            ContactCard(contact: contact)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tabBtn(_ t: Tab, label: String) -> some View {
        Button { tab = t } label: {
            Text(label)
                .font(.mono(10))
                .foregroundStyle(tab == t ? c.background : c.muted)
                .tracking(0.5)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(tab == t ? c.text : c.searchBg)
                .clipShape(Capsule())
        }
    }

    private var ringOpacity: Double { session.state == .scanning ? 1.0 : 0.3 }
    private func ringSize(_ opacity: Double) -> CGFloat { 88 + CGFloat((1.1 - opacity) * 100) }

    private var stateIcon: String {
        switch session.state {
        case .idle:       return "wave.3.right"
        case .starting:   return "wave.3.right"
        case .scanning:   return "wave.3.right"
        case .found:      return "person.fill.checkmark"
        case .confirming: return "clock"
        case .done:       return "checkmark"
        case .error:      return "exclamationmark"
        }
    }

    private var stateIconColor: Color {
        switch session.state {
        case .found:  return Color.fraiseGreen
        case .done:   return Color.fraiseGreen
        case .error:  return Color.fraiseRed
        default:      return c.muted
        }
    }

    private var stateTitle: String {
        switch session.state {
        case .idle:       return "meet in person"
        case .starting:   return "starting…"
        case .scanning:   return "hold phones together"
        case .found:      return "fraise user nearby"
        case .confirming: return "confirming…"
        case .done:       return "request sent"
        case .error:      return "something went wrong"
        }
    }

    private var stateSubtitle: String {
        switch session.state {
        case .idle:       return "tap start, then hold your phones together.\nboth of you need the app open."
        case .starting:   return "enabling bluetooth…"
        case .scanning:   return "looking for nearby fraise users."
        case .found:      return "tap confirm to send a connection request.\nyou'll both have 48 hours to approve."
        case .confirming: return "sending request…"
        case .done:       return "you both have 48 hours to independently approve.\nno pressure — you go home and decide."
        case .error(let m): return m
        }
    }

    // MARK: - Actions

    @MainActor private func startMeet() async {
        guard let token = Keychain.userToken else { return }
        session.stop()
        myToken = nil
        do {
            let t = try await APIClient.shared.getMeetingToken(token: token)
            myToken = t.token
            session.start(token: t.token)
        } catch {
            session.state = .error("couldn't get a meeting token")
        }
    }

    @MainActor private func confirm(theirToken: String) async {
        guard let token = Keychain.userToken, let myT = myToken else { return }
        session.state = .confirming
        do {
            try await APIClient.shared.recordMeeting(myToken: myT, theirToken: theirToken, token: token)
            session.stop()
            session.state = .done
            Haptics.notification(.success)
            await load()
        } catch {
            session.state = .error(error.localizedDescription)
        }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        async let p = try? await APIClient.shared.fetchPendingConnections(token: token)
        async let c = try? await APIClient.shared.fetchContacts(token: token)
        if let pp = await p { pending = pp }
        if let cc = await c { contacts = cc }
    }
}

// MARK: - Pending card

private struct PendingCard: View {
    @Environment(\.fraiseColors) private var c
    let connection: PendingConnection
    let onAction: () async -> Void
    @State private var inFlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.theirName?.lowercased() ?? connection.theirCode ?? "fraise user")
                        .font(.system(size: 16, design: .serif)).foregroundStyle(c.text)
                    if let code = connection.theirCode {
                        Text(code).font(.mono(10)).foregroundStyle(c.muted).tracking(0.5)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(c.muted)
                        Text(timeRemaining).font(.mono(10)).foregroundStyle(c.muted)
                    }
                }
                Spacer()
                if connection.iApproved {
                    Text("awaiting theirs")
                        .font(.mono(9)).foregroundStyle(c.muted).tracking(0.5)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(c.searchBg).clipShape(Capsule())
                }
            }
            .padding(Spacing.md)

            if !connection.iApproved {
                Divider().foregroundStyle(c.border).opacity(0.6)
                HStack(spacing: 0) {
                    actionButton("approve", color: Color.fraiseGreen, approve: true)
                    Divider().frame(width: 0.5).foregroundStyle(c.border)
                    actionButton("decline", color: Color.fraiseRed, approve: false)
                }
                .frame(height: 44)
            }
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
            connection.iApproved ? c.border : Color.fraiseGreen.opacity(0.3),
            lineWidth: 0.5))
        .disabled(inFlight)
    }

    private func actionButton(_ label: String, color: Color, approve: Bool) -> some View {
        Button {
            guard !inFlight, let token = Keychain.userToken else { return }
            inFlight = true
            Haptics.impact(.medium)
            Task {
                if approve {
                    try? await APIClient.shared.approveConnection(id: connection.id, token: token)
                } else {
                    try? await APIClient.shared.declineConnection(id: connection.id, token: token)
                }
                await onAction()
                inFlight = false
            }
        } label: {
            Text(inFlight ? "—" : label)
                .font(.mono(11, weight: .medium)).foregroundStyle(color)
                .frame(maxWidth: .infinity)
        }
    }

    private var timeRemaining: String {
        guard let expires = FraiseDateFormatter.date(from: connection.expiresAt) else { return "48h remaining" }
        let hours = Int(expires.timeIntervalSinceNow / 3600)
        return hours > 1 ? "\(hours)h remaining" : "< 1h remaining"
    }
}

// MARK: - Contact card

private struct ContactCard: View {
    @Environment(\.fraiseColors) private var c
    let contact: FraiseContact

    var body: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                Circle().fill(c.searchBg)
                    .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    .frame(width: 44, height: 44)
                Text(contact.name?.prefix(1).uppercased() ?? "·")
                    .font(.system(size: 18, design: .serif)).foregroundStyle(c.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.name?.lowercased() ?? contact.userCode ?? "member")
                        .font(.mono(14)).foregroundStyle(c.text)
                    if contact.verified ?? false {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9)).foregroundStyle(c.muted)
                    }
                }
                if let code = contact.userCode {
                    Text(code).font(.mono(10)).foregroundStyle(c.muted).tracking(0.5)
                }
            }
            Spacer()
            if let met = contact.metAt {
                Text(FraiseDateFormatter.medium(met)).font(.mono(10)).foregroundStyle(c.muted)
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
    }

}
