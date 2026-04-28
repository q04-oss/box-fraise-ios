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
            HStack {
                FraiseBackButton { state.panel = .home }
                Spacer()
                Text("staff")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(c.text)
                Spacer()
                Button { Task { await load() } } label: {
                    Text("↻")
                        .font(.mono(16))
                        .foregroundStyle(c.muted)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if state.staffPin.isEmpty {
                pinEntry
            } else {
                VStack(spacing: 0) {
                    Button { state.panel = .walkIn } label: {
                        HStack {
                            Text("walk-in order")
                                .font(.mono(12))
                                .foregroundStyle(c.text)
                            Spacer()
                            Text("→").font(.mono(12)).foregroundStyle(c.muted)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 12)
                    }
                    Divider().foregroundStyle(c.border).opacity(0.6)
                }
                ordersList
            }
        }
    }

    // MARK: - PIN entry

    private var pinEntry: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("staff PIN")
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(c.text)

            SecureField("enter PIN", text: $pin)
                .font(.mono(16))
                .foregroundStyle(c.text)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(c.searchBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
                .keyboardType(.numberPad)
                .onPasteCommand(of: []) { _ in }  // block paste

            if let error {
                Text(error)
                    .font(.mono(11))
                    .foregroundStyle(Color(hex: "C0392B"))
            }

            Button {
                Task { await submitPin() }
            } label: {
                HStack {
                    if loading { ProgressView().tint(.white) }
                    Text("sign in →")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(c.text)
                .clipShape(Capsule())
            }
            .disabled(loading || pin.isEmpty)
        }
        .padding(Spacing.md)
    }

    // MARK: - Orders list

    private var ordersList: some View {
        VStack(spacing: 0) {
            // Status filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statuses, id: \.self) { s in
                        Button {
                            statusFilter = s
                        } label: {
                            Text(s)
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
                VStack {
                    Text("no \(statusFilter == "all" ? "" : statusFilter + " ")orders")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredOrders) { order in
                        StaffOrderRow(order: order)
                            .listRowBackground(c.background)
                            .listRowSeparatorTint(c.border)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    @MainActor private func submitPin() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        error = nil
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

// MARK: - Staff Order Row

struct StaffOrderRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let order: StaffOrder
    @State private var actionInFlight = false

    private var nextAction: (label: String, action: String)? {
        switch order.status {
        case "paid":       return ("prepare", "prepare")
        case "preparing":  return ("ready",   "ready")
        case "ready":      return ("collect", "collect")
        default:           return nil
        }
    }

    private var statusColor: Color {
        switch order.status {
        case "collected": return Color(hex: "4CAF50")
        case "ready":     return Color(hex: "2196F3")
        case "preparing": return Color(hex: "FF9800")
        default:          return c.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.summary)
                        .font(.mono(13))
                        .foregroundStyle(c.text)
                    Text("× \(order.quantity)")
                        .font(.mono(11))
                        .foregroundStyle(c.muted)
                    if let email = order.customerEmail {
                        Text(email)
                            .font(.mono(10))
                            .foregroundStyle(c.muted)
                    }
                }
                Spacer()
                Text(order.status)
                    .font(.mono(9))
                    .foregroundStyle(statusColor)
                    .tracking(1)
                    .textCase(.uppercase)
            }

            if let next = nextAction {
                Button {
                    guard !actionInFlight else { return }
                    actionInFlight = true
                    Task { @MainActor in
                        defer { actionInFlight = false }
                        await APIClient.shared.staffAction(next.action, orderId: order.id, pin: state.staffPin)
                        if let token = Keychain.userToken,
                           let orders = try? await APIClient.shared.fetchStaffOrders(pin: state.staffPin, token: token) {
                            state.staffOrders = orders
                        }
                    }
                } label: {
                    Text(next.label + " →")
                        .font(.mono(11))
                        .foregroundStyle(c.background)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(c.text)
                        .clipShape(Capsule())
                }
                .disabled(actionInFlight)
            }
        }
        .padding(.vertical, 8)
    }
}
