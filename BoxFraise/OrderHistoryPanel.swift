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
    @State private var receipt: OrderReceipt?
    @State private var receiptLoading = false
    @State private var receiptExpanded = false

    private var statusColor: Color {
        switch order.status {
        case "collected":           return Color(hex: "4CAF50")
        case "ready":               return Color(hex: "2196F3")
        case "preparing", "paid":   return c.muted
        default:                    return c.border
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
                Divider().foregroundStyle(c.border).opacity(0.6)
                receiptToggle
                if receiptExpanded {
                    if let r = receipt {
                        receiptView(r)
                    } else if receiptLoading {
                        HStack {
                            ProgressView().tint(c.muted).scaleEffect(0.7)
                            Text("loading receipt…")
                                .font(.mono(10)).foregroundStyle(c.muted)
                        }
                        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
                    }
                }
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

    private var receiptToggle: some View {
        Button {
            receiptExpanded.toggle()
            if receiptExpanded && receipt == nil && !receiptLoading {
                Task { await loadReceipt() }
            }
        } label: {
            HStack {
                Text(receiptLoading ? "—" : "receipt")
                    .font(.mono(10)).foregroundStyle(c.muted)
                Spacer()
                Image(systemName: receiptExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10)).foregroundStyle(c.muted)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        }
    }

    private func receiptView(_ r: OrderReceipt) -> some View {
        VStack(spacing: 0) {
            if let loc = r.locationName   { receiptRow("location",    value: loc.lowercased()) }
            if let w = r.worker?.displayName { receiptRow("prepared by", value: w.lowercased()) }
            if let p = r.seasonPatron?.displayName { receiptRow("patron", value: p.lowercased()) }
            if let t = r.nfcToken         { receiptRow("token",       value: String(t.prefix(8)) + "…") }
        }
        .padding(.horizontal, Spacing.md).padding(.bottom, Spacing.sm)
    }

    private func receiptRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mono(9)).foregroundStyle(c.muted).tracking(1).textCase(.uppercase)
                .frame(width: 80, alignment: .leading)
            Text(value).font(.mono(11)).foregroundStyle(c.text)
            Spacer()
        }
        .padding(.vertical, 6)
    }

    @MainActor private func loadReceipt() async {
        guard let token = Keychain.userToken else { return }
        receiptLoading = true
        receipt = try? await APIClient.shared.fetchOrderReceipt(orderId: order.id, token: token)
        receiptLoading = false
    }
}
