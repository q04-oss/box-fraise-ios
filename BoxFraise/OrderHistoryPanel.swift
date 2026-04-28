import SwiftUI

struct OrderHistoryPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FraiseBackButton { state.panel = .profile }
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

            if loading && state.orderHistory.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<5, id: \.self) { _ in FraiseSkeletonRow(wide: true) }
                    }
                    .padding(Spacing.md)
                }
            } else if let err = loadError {
                VStack(spacing: 12) {
                    Text(err)
                        .font(.mono(12)).foregroundStyle(Color(hex: "C0392B"))
                        .multilineTextAlignment(.center)
                    Button { Task { await load() } } label: {
                        Text("retry")
                            .font(.mono(12)).foregroundStyle(c.muted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(c.searchBg).clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Spacing.md)
            } else if state.orderHistory.isEmpty {
                FraiseEmptyState(
                    icon: "bag",
                    title: "no orders yet",
                    subtitle: "your box fraise orders will appear here after your first purchase."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.orderHistory) { order in
                            OrderHistoryCard(order: order)
                        }
                    }
                    .padding(Spacing.md)
                }
                .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true; loadError = nil
        defer { loading = false }
        do {
            state.orderHistory = try await APIClient.shared.fetchOrderHistory(token: token)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Card

struct OrderHistoryCard: View {
    @Environment(\.fraiseColors) private var c
    let order: PastOrder
    @State private var displayRating: Int?
    @State private var ratingDone = false

    private var statusColor: Color {
        switch order.status {
        case "collected": return Color(hex: "4CAF50")
        case "ready":     return Color(hex: "2196F3")
        case "preparing": return Color(hex: "FF9800")
        default:          return c.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(order.varietyName.lowercased())
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(c.text)

                    Text([order.chocolate, order.finish, "×\(order.quantity)"]
                        .joined(separator: " · ").lowercased())
                        .font(.mono(11)).foregroundStyle(c.muted)

                    if let date = order.slotDate {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10)).foregroundStyle(c.muted)
                            Text(date).font(.mono(10)).foregroundStyle(c.muted)
                            if let time = order.slotTime {
                                Text("·").font(.mono(10)).foregroundStyle(c.border)
                                Text(time).font(.mono(10)).foregroundStyle(c.muted)
                            }
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(order.totalFormatted)
                        .font(.mono(13)).foregroundStyle(c.text)
                    Text(order.status)
                        .font(.mono(9)).foregroundStyle(statusColor).tracking(1)
                        .textCase(.uppercase)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(statusColor.opacity(0.1)).clipShape(Capsule())
                }
            }
            .padding(Spacing.md)

            if order.isCollected {
                Divider().foregroundStyle(c.border).opacity(0.6)
                starRow
            }
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        .onAppear { displayRating = order.rating }
    }

    private var starRow: some View {
        let shown = displayRating ?? 0
        return HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    guard !ratingDone else { return }
                    displayRating = star
                    ratingDone = true
                    Task { try? await APIClient.shared.rateOrder(id: order.id, rating: star, token: Keychain.userToken ?? "") }
                } label: {
                    Image(systemName: star <= shown ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(star <= shown ? Color(hex: "F9A825") : c.border)
                }
                .disabled(ratingDone && displayRating != nil)
            }
            Spacer()
            if ratingDone {
                Text("thanks")
                    .font(.mono(10)).foregroundStyle(c.muted)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
    }
}
