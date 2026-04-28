import SwiftUI

struct OrderHistoryPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { state.panel = .profile } label: {
                    Text("← back")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                }
                Spacer()
                Text("orders")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if loading {
                ProgressView().tint(c.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Text(err)
                        .font(.mono(12))
                        .foregroundStyle(Color(hex: "C0392B"))
                        .multilineTextAlignment(.center)
                    Button { Task { await load() } } label: {
                        Text("retry")
                            .font(.mono(12))
                            .foregroundStyle(c.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.md)
            } else if state.orderHistory.isEmpty {
                VStack {
                    Text("no orders yet")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.orderHistory) { order in
                        OrderHistoryRow(order: order)
                            .listRowBackground(c.background)
                            .listRowSeparatorTint(c.border)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            state.orderHistory = try await APIClient.shared.fetchOrderHistory(token: token)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Row

struct OrderHistoryRow: View {
    @Environment(\.fraiseColors) private var c
    let order: PastOrder

    private var statusColor: Color {
        order.isCollected ? Color(hex: "4CAF50") : c.muted
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(order.varietyName.lowercased())
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(c.text)

                Text([order.chocolate, order.finish, "×\(order.quantity)"].joined(separator: " · ").lowercased())
                    .font(.mono(11))
                    .foregroundStyle(c.muted)

                if let date = order.slotDate {
                    Text(date)
                        .font(.mono(10))
                        .foregroundStyle(c.muted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(order.totalFormatted)
                    .font(.mono(13))
                    .foregroundStyle(c.text)
                Text(order.status)
                    .font(.mono(9))
                    .foregroundStyle(statusColor)
                    .tracking(1)
                    .textCase(.uppercase)
            }
        }
        .padding(.vertical, 8)
    }
}
