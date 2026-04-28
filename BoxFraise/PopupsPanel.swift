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

                Text("popups")
                    .font(.system(size: 28, design: .serif))
                    .foregroundStyle(c.text)

                Text("pay to join · date set once threshold is met")
                    .font(.mono(10))
                    .foregroundStyle(c.muted)
                    .tracking(0.5)

                if let err = error {
                    Text(err)
                        .font(.mono(11))
                        .foregroundStyle(Color(hex: "C0392B"))
                        .onTapGesture { error = nil }
                }

                if state.popups.isEmpty {
                    Text("no popups open right now")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
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

    private var badgeColor: Color {
        if popup.isConfirmed   { return Color(hex: "388E3C") }
        if popup.isThresholdMet { return Color(hex: "F57F17") }
        return c.muted
    }

    private var badgeLabel: String {
        if popup.isConfirmed    { return "scheduled" }
        if popup.isThresholdMet { return "going ahead" }
        return "open"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(popup.businessName)
                        .font(.mono(9))
                        .foregroundStyle(c.muted)
                        .tracking(1.5)
                        .textCase(.uppercase)
                    Text(popup.title)
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(c.text)
                }
                Spacer()
                Text(badgeLabel)
                    .font(.mono(9))
                    .foregroundStyle(badgeColor)
                    .tracking(0.5)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(badgeColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            if let desc = popup.description {
                Text(desc)
                    .font(.mono(12))
                    .foregroundStyle(c.muted)
                    .lineLimit(3)
            }

            if popup.isConfirmed, let date = popup.eventDate {
                Text(date)
                    .font(.mono(12))
                    .foregroundStyle(Color(hex: "388E3C"))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(c.searchBg)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(popup.isThresholdMet || popup.isConfirmed ? Color(hex: "4CAF50") : c.text)
                        .frame(width: geo.size.width * popup.thresholdPct, height: 3)
                }
            }
            .frame(height: 3)

            Text("\(popup.seatsClaimed) of \(popup.minSeats) needed · \(popup.seatsClaimed)/\(popup.maxSeats) joined")
                .font(.mono(10))
                .foregroundStyle(c.muted)

            HStack {
                Text(popup.priceFormatted + " per person")
                    .font(.mono(13))
                    .foregroundStyle(c.text)
                Spacer()
                if popup.isOpen && popup.seatsClaimed < popup.maxSeats {
                    if let sheet = paymentSheet {
                        PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                            handlePayment(result)
                        } label: {
                            joinLabel
                        }
                    } else {
                        Button {
                            guard state.isSignedIn else { state.panel = .auth; return }
                            Task { await prepareJoin() }
                        } label: {
                            joinLabel
                        }
                        .disabled(joining == popup.id)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
    }

    private var joinLabel: some View {
        Text(joining == popup.id ? "—" : "join · \(popup.priceFormatted)")
            .font(.mono(12))
            .foregroundStyle(c.background)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(c.text)
            .clipShape(Capsule())
    }

    @MainActor private func prepareJoin() async {
        guard let token = Keychain.userToken else { return }
        joining = popup.id
        error = nil
        defer { if paymentSheet == nil { joining = nil } }
        do {
            let response = try await APIClient.shared.joinPopup(id: popup.id, token: token)
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Box Fraise"
            config.applePay = .init(merchantId: "merchant.com.boxfraise.app", merchantCountryCode: "CA")
            paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
        } catch {
            self.error = error.localizedDescription
            joining = nil
        }
    }

    @MainActor private func handlePayment(_ result: PaymentSheetResult) {
        paymentSheet = nil
        joining = nil
        switch result {
        case .completed:
            Task { @MainActor in
                guard let token = Keychain.userToken else { return }
                do {
                    try await APIClient.shared.confirmPopupJoin(id: popup.id, token: token)
                    await state.refresh()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        case .failed(let e):
            error = e.localizedDescription
        case .canceled:
            break
        }
    }
}
