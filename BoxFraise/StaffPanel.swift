import SwiftUI

struct StaffPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var pin = ""
    @State private var loading = false
    @State private var error: String?
    @State private var statusFilter = "all"

    private let statuses = ["all", "paid", "preparing", "ready", "collected"]

    private var filteredOrders: [StaffOrder] {
        statusFilter == "all"
            ? state.staffOrders
            : state.staffOrders.filter { $0.status == statusFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                FraiseBackButton { state.panel = .home }
                Spacer()
                Text("staff")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(c.text)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.muted)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if state.staffPin.isEmpty {
                pinEntry
            } else {
                ordersList
            }
        }
    }

    // MARK: - PIN entry

    private var pinEntry: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("staff access")
                    .font(.system(size: 28, design: .serif))
                    .foregroundStyle(c.text)
                Text("enter your PIN to view and manage orders")
                    .font(.mono(11))
                    .foregroundStyle(c.muted)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: 6) {
                FraiseSectionLabel(text: "pin")
                SecureField("••••••", text: $pin)
                    .font(.mono(20))
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 14)
                    .background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
                    .keyboardType(.numberPad)
                    .onPasteCommand(of: []) { _ in }
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "C0392B"))
                    Text(error)
                        .font(.mono(11))
                        .foregroundStyle(Color(hex: "C0392B"))
                }
            }

            Button { Task { await submitPin() } } label: {
                HStack {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "—" : "enter")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(.white)
                    if !loading {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 16)
                .background(pin.isEmpty ? c.border : c.text)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(loading || pin.isEmpty)
        }
        .padding(Spacing.md)
    }

    // MARK: - Orders list

    private var ordersList: some View {
        VStack(spacing: 0) {
            // Walk-in shortcut
            Button { state.panel = .walkIn } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(c.muted)
                    Text("walk-in order")
                        .font(.mono(12))
                        .foregroundStyle(c.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.border)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 12)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            // Status filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(statuses, id: \.self) { s in
                        let cnt = s == "all"
                            ? state.staffOrders.count
                            : state.staffOrders.filter { $0.status == s }.count
                        Button { statusFilter = s } label: {
                            Text(cnt > 0 ? "\(s) \(cnt)" : s)
                                .font(.mono(10))
                                .foregroundStyle(statusFilter == s ? c.background : c.muted)
                                .tracking(0.5)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(statusFilter == s ? c.text : c.searchBg)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 10)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            if filteredOrders.isEmpty {
                FraiseEmptyState(
                    icon: "tray",
                    title: "no \(statusFilter == "all" ? "" : statusFilter + " ")orders",
                    subtitle: ""
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredOrders) { order in
                            StaffOrderCard(order: order)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    // MARK: - Actions

    @MainActor private func submitPin() async {
        guard let token = Keychain.userToken else { return }
        loading = true; error = nil
        do {
            let orders = try await APIClient.shared.fetchStaffOrders(pin: pin, token: token)
            state.staffPin = pin
            state.staffOrders = orders
        } catch {
            self.error = "invalid PIN"
        }
        loading = false
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken, !state.staffPin.isEmpty else { return }
        if let orders = try? await APIClient.shared.fetchStaffOrders(pin: state.staffPin, token: token) {
            state.staffOrders = orders
        }
    }
}

// MARK: - Staff Order Card

struct StaffOrderCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let order: StaffOrder
    @State private var actionInFlight = false

    private var nextAction: (label: String, action: String)? {
        switch order.status {
        case "paid":      return ("prepare", "prepare")
        case "preparing": return ("mark ready", "ready")
        case "ready":     return ("collected", "collect")
        default:          return nil
        }
    }

    private var statusColor: Color {
        switch order.status {
        case "collected": return Color(hex: "4CAF50")
        case "ready":     return Color(hex: "2196F3")
        case "preparing": return Color(hex: "FF9800")
        case "paid":      return c.muted
        default:          return c.border
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Order info
            HStack(alignment: .top, spacing: Spacing.sm) {
                // Status indicator strip
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if let variety = order.varietyName {
                        Text(variety.lowercased())
                            .font(.system(size: 16, design: .serif))
                            .foregroundStyle(c.text)
                    }

                    Text([order.chocolate, order.finish]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                        .lowercased()
                    )
                    .font(.mono(11))
                    .foregroundStyle(c.muted)

                    HStack(spacing: 8) {
                        Label("\(order.quantity)", systemImage: "cube.box")
                            .font(.mono(10))
                            .foregroundStyle(c.muted)

                        if let total = order.totalCents {
                            Text(String(format: "CA$%.2f", Double(total) / 100))
                                .font(.mono(10))
                                .foregroundStyle(c.muted)
                        }

                        if let slot = order.slotTime {
                            Label(slot, systemImage: "clock")
                                .font(.mono(10))
                                .foregroundStyle(c.muted)
                        }
                    }

                    if let email = order.customerEmail {
                        Text(email.lowercased())
                            .font(.mono(10))
                            .foregroundStyle(c.border)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(order.status)
                    .font(.mono(9))
                    .foregroundStyle(statusColor)
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(Spacing.md)

            // Action button
            if let next = nextAction {
                Divider().foregroundStyle(c.border).opacity(0.6)

                Button {
                    guard !actionInFlight else { return }
                    actionInFlight = true
                    Haptics.impact(.medium)
                    Task { @MainActor in
                        defer { actionInFlight = false }
                        await APIClient.shared.staffAction(next.action, orderId: order.id, pin: state.staffPin)
                        if let token = Keychain.userToken,
                           let orders = try? await APIClient.shared.fetchStaffOrders(pin: state.staffPin, token: token) {
                            state.staffOrders = orders
                        }
                    }
                } label: {
                    HStack {
                        Text(actionInFlight ? "—" : next.label)
                            .font(.mono(12, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        if !actionInFlight {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 12)
                    .background(statusColor)
                }
                .disabled(actionInFlight)
            }
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
    }
}
