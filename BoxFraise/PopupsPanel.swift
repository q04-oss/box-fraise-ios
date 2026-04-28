import SwiftUI
import StripePaymentSheet

struct PopupsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var joining: Int? = nil
    @State private var error: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                FraiseBackButton { state.panel = .home }

                VStack(alignment: .leading, spacing: 4) {
                    Text("popups")
                        .font(.system(size: 28, design: .serif))
                        .foregroundStyle(c.text)
                    Text("pay to join · date confirmed once threshold is met")
                        .font(.mono(10))
                        .foregroundStyle(c.muted)
                        .tracking(0.3)
                }

                if let err = error {
                    Text(err)
                        .font(.mono(11))
                        .foregroundStyle(Color(hex: "C0392B"))
                        .onTapGesture { error = nil }
                }

                if state.popups.isEmpty {
                    FraiseEmptyState(
                        icon: "calendar.badge.clock",
                        title: "nothing scheduled yet",
                        subtitle: "new popups will appear here when they open for registration."
                    )
                } else {
                    ForEach(state.popups) { popup in
                        PopupCard(popup: popup, joining: $joining, error: $error)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
        .task { await state.refresh() }
    }
}

// MARK: - Popup Card

struct PopupCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let popup: FraisePopup
    @Binding var joining: Int?
    @Binding var error: String?
    @State private var paymentSheet: PaymentSheet?

    private var statusColor: Color {
        if popup.isConfirmed    { return Color(hex: "388E3C") }
        if popup.isThresholdMet { return Color(hex: "F57F17") }
        return c.muted
    }

    private var statusLabel: String {
        if popup.isConfirmed    { return "scheduled" }
        if popup.isThresholdMet { return "going ahead" }
        return "open"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(popup.businessName.lowercased())
                            .font(.mono(9))
                            .foregroundStyle(c.muted)
                            .tracking(1.5)
                            .textCase(.uppercase)
                        Text(popup.title.lowercased())
                            .font(.system(size: 18, design: .serif))
                            .foregroundStyle(c.text)
                    }
                    Spacer()
                    Text(statusLabel)
                        .font(.mono(9))
                        .foregroundStyle(statusColor)
                        .tracking(0.5)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(statusColor.opacity(0.1))
                        .clipShape(Capsule())
                }

                if let desc = popup.description {
                    Text(desc.lowercased())
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                        .lineSpacing(3)
                        .lineLimit(3)
                }

                if popup.isConfirmed, let date = popup.eventDate {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "388E3C"))
                        Text(date)
                            .font(.mono(11))
                            .foregroundStyle(Color(hex: "388E3C"))
                    }
                }
            }
            .padding(Spacing.md)

            // ── Progress ──────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(c.searchBg).frame(height: 4)
                        Capsule()
                            .fill(popup.isThresholdMet || popup.isConfirmed
                                  ? Color(hex: "4CAF50") : c.text)
                            .frame(width: geo.size.width * popup.thresholdPct, height: 4)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: popup.thresholdPct)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text("\(popup.seatsClaimed) of \(popup.minSeats) needed")
                        .font(.mono(10)).foregroundStyle(c.muted)
                    Spacer()
                    Text("\(popup.maxSeats - popup.seatsClaimed) spots left")
                        .font(.mono(10)).foregroundStyle(c.muted)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)

            // ── CTA ───────────────────────────────────────────────────────────
            if popup.isOpen && popup.seatsClaimed < popup.maxSeats {
                Divider().foregroundStyle(c.border).opacity(0.6)

                if let sheet = paymentSheet {
                    PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                        handlePayment(result)
                    } label: { joinButton }
                } else {
                    Button {
                        guard state.isSignedIn else { state.panel = .auth; return }
                        Task { await prepareJoin() }
                    } label: { joinButton }
                    .disabled(joining == popup.id)
                }
            } else if popup.isConfirmed {
                Divider().foregroundStyle(c.border).opacity(0.6)
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "388E3C"))
                    Text("you're in")
                        .font(.mono(12))
                        .foregroundStyle(Color(hex: "388E3C"))
                    Spacer()
                    Text(popup.priceFormatted)
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
            }
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.border, lineWidth: 0.5))
    }

    private var joinButton: some View {
        HStack {
            Text(joining == popup.id ? "—" : "join")
                .font(.mono(13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            if joining != popup.id {
                Text(popup.priceFormatted)
                    .font(.mono(12))
                    .foregroundStyle(.white.opacity(0.7))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .background(c.text)
    }

    @MainActor private func prepareJoin() async {
        guard let token = Keychain.userToken else { return }
        joining = popup.id; error = nil
        defer { if paymentSheet == nil { joining = nil } }
        do {
            let response = try await APIClient.shared.joinPopup(id: popup.id, token: token)
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Box Fraise"
            config.applePay = .init(merchantId: "merchant.com.boxfraise.app", merchantCountryCode: "CA")
            paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
        } catch {
            self.error = error.localizedDescription; joining = nil
        }
    }

    @MainActor private func handlePayment(_ result: PaymentSheetResult) {
        paymentSheet = nil; joining = nil
        switch result {
        case .completed:
            Haptics.notification(.success)
            Task { @MainActor in
                guard let token = Keychain.userToken else { return }
                do {
                    try await APIClient.shared.confirmPopupJoin(id: popup.id, token: token)
                    await state.refresh()
                } catch { self.error = error.localizedDescription }
            }
        case .failed(let e):
            Haptics.notification(.error)
            error = e.localizedDescription
        case .canceled: break
        }
    }
}
