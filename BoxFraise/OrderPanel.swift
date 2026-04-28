import SwiftUI
import StripePaymentSheet

struct OrderPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    @State private var paymentSheet: PaymentSheet?
    @State private var loading = false
    @State private var error: String?

    private var order: OrderState { state.orderState }

    private var step: OrderStep {
        if state.confirmedOrder != nil         { return .confirmed }
        if order.varietyId == nil              { return .variety }
        if order.chocolate == nil              { return .chocolate }
        if order.finish == nil                 { return .finish }
        return .review
    }

    enum OrderStep { case variety, chocolate, finish, review, confirmed }

    var body: some View {
        VStack(spacing: 0) {
            // Header strip
            HStack {
                Button { state.clearLocation() } label: {
                    Text("← map")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                }
                Spacer()
                if let loc = state.activeLocation {
                    Text(loc.name.lowercased())
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(c.text)
                        .tracking(0.3)
                }
                Spacer()
                // Balance placeholder
                Text("")
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    switch step {
                    case .variety:    varietyStep
                    case .chocolate:  chocolateStep
                    case .finish:     finishStep
                    case .review:     reviewStep
                    case .confirmed:  confirmedStep
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    // MARK: - Variety step

    private var varietyStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            stepLabel("strawberry")
            if state.varieties.isEmpty {
                ProgressView().tint(c.muted)
            } else {
                ForEach(state.varieties) { v in
                    selectionRow(
                        title: v.name,
                        subtitle: v.description ?? "",
                        trailing: v.priceFormatted,
                        selected: order.varietyId == v.id
                    ) {
                        state.orderState.varietyId = v.id
                        state.orderState.varietyName = v.name
                        state.orderState.priceCents = v.priceCents
                    }
                }
            }
        }
    }

    // MARK: - Chocolate step

    private var chocolateStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            backButton { state.orderState.varietyId = nil }
            stepLabel("chocolate")
            ForEach(CHOCOLATES, id: \.id) { choc in
                selectionRow(
                    title: choc.name,
                    subtitle: "",
                    trailing: "",
                    selected: order.chocolate == choc.id
                ) {
                    state.orderState.chocolate = choc.id
                    state.orderState.chocolateName = choc.name
                }
            }
        }
    }

    // MARK: - Finish step

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            backButton { state.orderState.chocolate = nil }
            stepLabel("finish")
            ForEach(FINISHES, id: \.id) { fin in
                selectionRow(
                    title: fin.name,
                    subtitle: "",
                    trailing: "",
                    selected: order.finish == fin.id
                ) {
                    state.orderState.finish = fin.id
                    state.orderState.finishName = fin.name
                }
            }
        }
    }

    // MARK: - Review step

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            backButton { state.orderState.finish = nil }
            stepLabel("review")

            VStack(spacing: 0) {
                reviewRow("variety",   value: order.varietyName ?? "")
                reviewRow("chocolate", value: order.chocolateName ?? "")
                reviewRow("finish",    value: order.finishName ?? "")
            }
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

            // Quantity
            HStack {
                Text("quantity")
                    .font(.mono(11))
                    .foregroundStyle(c.muted)
                    .tracking(1)
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        if state.orderState.quantity > 1 { state.orderState.quantity -= 1 }
                    } label: {
                        Text("−").font(.mono(18)).foregroundStyle(c.text)
                    }
                    Text("\(order.quantity)")
                        .font(.mono(18, weight: .medium))
                        .foregroundStyle(c.text)
                        .frame(minWidth: 20, alignment: .center)
                    Button {
                        if state.orderState.quantity < 24 { state.orderState.quantity += 1 }
                    } label: {
                        Text("+").font(.mono(18)).foregroundStyle(c.text)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.mono(11))
                    .foregroundStyle(Color(hex: "C0392B"))
            }

            // Total + pay button
            VStack(spacing: 10) {
                HStack {
                    Text("total")
                        .font(.mono(11))
                        .foregroundStyle(c.muted)
                        .tracking(1)
                        .textCase(.uppercase)
                    Spacer()
                    Text("CA$\(String(format: "%.2f", Double(order.totalCents) / 100))")
                        .font(.mono(16, weight: .medium))
                        .foregroundStyle(c.text)
                }

                if let sheet = paymentSheet {
                    PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                        handlePaymentResult(result)
                    } label: {
                        payButtonLabel
                    }
                } else {
                    Button {
                        guard state.isSignedIn else { state.panel = .auth; return }
                        Task { await preparePayment() }
                    } label: {
                        payButtonLabel
                    }
                    .disabled(loading)
                }
            }
        }
    }

    private var payButtonLabel: some View {
        HStack {
            if loading { ProgressView().tint(.white) }
            Text(loading ? "—" : "pay  →")
                .font(.mono(14, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(c.text)
        .clipShape(Capsule())
    }

    // MARK: - Confirmed step

    private var confirmedStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("confirmed")
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(c.text)
            if let confirmed = state.confirmedOrder {
                Text(confirmed.varietyName?.lowercased() ?? "your order")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }
            Text("you'll receive a notification when your box is ready.")
                .font(.mono(12))
                .foregroundStyle(c.muted)
                .lineSpacing(4)

            Button {
                state.confirmedOrder = nil
                state.orderState.reset()
            } label: {
                Text("order again")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }
            .padding(.top, Spacing.sm)
        }
    }

    // MARK: - Helpers

    private func stepLabel(_ label: String) -> some View {
        Text(label)
            .font(.mono(9))
            .foregroundStyle(c.muted)
            .tracking(1.5)
            .textCase(.uppercase)
    }

    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("← back")
                .font(.mono(12))
                .foregroundStyle(c.muted)
        }
    }

    private func selectionRow(title: String, subtitle: String, trailing: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.mono(14))
                        .foregroundStyle(c.text)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.mono(11))
                            .foregroundStyle(c.muted)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                }
                Circle()
                    .strokeBorder(selected ? c.text : c.border, lineWidth: selected ? 5 : 1)
                    .frame(width: 18, height: 18)
            }
            .padding(Spacing.md)
            .background(selected ? c.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? c.border : c.border.opacity(0.5), lineWidth: 0.5))
        }
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mono(11))
                .foregroundStyle(c.muted)
                .tracking(1)
                .textCase(.uppercase)
            Spacer()
            Text(value.lowercased())
                .font(.mono(13))
                .foregroundStyle(c.text)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }

    // MARK: - Payment

    @MainActor private func preparePayment() async {
        guard let token = Keychain.userToken,
              let loc = state.activeLocation,
              let locId = loc.locationId ?? Optional(loc.id),
              let varId = order.varietyId,
              let choc = order.chocolate,
              let fin = order.finish else { return }

        loading = true
        error = nil
        defer { loading = false }

        do {
            let response = try await APIClient.shared.createOrder(
                locationId: locId, varietyId: varId,
                chocolate: choc, finish: fin,
                quantity: order.quantity, token: token
            )

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Box Fraise"
            config.applePay = .init(merchantId: "merchant.com.boxfraise.app", merchantCountryCode: "CA")

            let sheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
            paymentSheet = sheet
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        DispatchQueue.main.async {
            switch result {
            case .canceled:
                self.paymentSheet = nil
            case .failed(let e):
                self.error = e.localizedDescription
                self.paymentSheet = nil
            case .completed:
                self.paymentSheet = nil
                Task { @MainActor in
                    self.state.confirmedOrder = ConfirmedOrder(id: 0, status: "confirmed", varietyName: self.order.varietyName)
                }
            }
        }
    }
}
