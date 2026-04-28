import SwiftUI
import StripePaymentSheet

struct OrderPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    @State private var paymentSheet: PaymentSheet?
    @State private var loading = false
    @State private var error: String?
    @State private var goingForward = true
    @State private var highlightedVarietyId: Int?
    @State private var highlightedChocolate: String?
    @State private var highlightedFinish: String?
    @State private var pendingOrderId: Int?

    private var order: OrderState { state.orderState }

    private var step: OrderStep {
        if state.confirmedOrder != nil { return .confirmed }
        if order.varietyId == nil      { return .variety }
        if order.chocolate == nil      { return .chocolate }
        if order.finish == nil         { return .finish }
        return .review
    }

    enum OrderStep: Int { case variety, chocolate, finish, review, confirmed }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    goingForward = false
                    state.clearLocation()
                } label: {
                    Text("← map").font(.mono(12)).foregroundStyle(c.muted)
                }
                Spacer()
                if let loc = state.activeLocation {
                    Text(loc.name.lowercased())
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(c.text)
                        .tracking(0.3)
                }
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            // Step progress bar (hidden on confirmed)
            if step != .confirmed {
                stepBar
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 12)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            // Step content with directional transitions
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    stepContent
                        .id(step.rawValue)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: goingForward ? 30 : -30)),
                            removal:   .opacity.combined(with: .offset(x: goingForward ? -20 : 20))
                        ))
                        .animation(.spring(response: 0.3, dampingFraction: 0.88), value: step.rawValue)
                }
                .padding(Spacing.md)
            }
        }
    }

    // MARK: - Step bar

    private var stepBar: some View {
        HStack(spacing: 5) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i <= step.rawValue ? c.text : c.border)
                    .frame(width: i == step.rawValue ? 24 : 6, height: 4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step.rawValue)
            }
            Spacer()
        }
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .variety:   varietyStep
        case .chocolate: chocolateStep
        case .finish:    finishStep
        case .review:    reviewStep
        case .confirmed: confirmedStep
        }
    }

    // MARK: - Variety

    private var varietyStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FraiseSectionLabel(text: "strawberry")
            if state.varieties.isEmpty {
                VStack(spacing: 8) {
                    FraiseSkeletonRow(wide: true)
                    FraiseSkeletonRow()
                    FraiseSkeletonRow(wide: true)
                }
                .padding(.top, 4)
            } else {
                ForEach(state.varieties) { v in
                    selectionRow(
                        title: v.name, subtitle: v.description ?? "",
                        trailing: v.priceFormatted,
                        selected: (order.varietyId ?? highlightedVarietyId) == v.id
                    ) {
                        Haptics.selection()
                        goingForward = true
                        highlightedVarietyId = v.id
                        state.orderState.varietyName = v.name
                        state.orderState.priceCents = v.priceCents
                        paymentSheet = nil; error = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            state.orderState.varietyId = v.id
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chocolate

    private var chocolateStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FraiseBackButton {
                goingForward = false
                highlightedVarietyId = nil
                state.orderState.varietyId = nil
            }
            FraiseSectionLabel(text: "chocolate")
            ForEach(CHOCOLATES, id: \.id) { choc in
                selectionRow(
                    title: choc.name, subtitle: "", trailing: "",
                    selected: (order.chocolate ?? highlightedChocolate) == choc.id
                ) {
                    Haptics.selection()
                    goingForward = true
                    highlightedChocolate = choc.id
                    state.orderState.chocolateName = choc.name
                    paymentSheet = nil; error = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        state.orderState.chocolate = choc.id
                    }
                }
            }
        }
    }

    // MARK: - Finish

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            FraiseBackButton {
                goingForward = false
                highlightedChocolate = nil
                state.orderState.chocolate = nil
            }
            FraiseSectionLabel(text: "finish")
            ForEach(FINISHES, id: \.id) { fin in
                selectionRow(
                    title: fin.name, subtitle: "", trailing: "",
                    selected: (order.finish ?? highlightedFinish) == fin.id
                ) {
                    Haptics.selection()
                    goingForward = true
                    highlightedFinish = fin.id
                    state.orderState.finishName = fin.name
                    paymentSheet = nil; error = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        state.orderState.finish = fin.id
                    }
                }
            }
        }
    }

    // MARK: - Review

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            FraiseBackButton {
                goingForward = false
                highlightedFinish = nil
                state.orderState.finish = nil
            }
            FraiseSectionLabel(text: "review")

            // Summary card
            VStack(spacing: 0) {
                reviewRow("strawberry", value: order.varietyName ?? "")
                reviewRow("chocolate",  value: order.chocolateName ?? "")
                reviewRow("finish",     value: order.finishName ?? "")
            }
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

            // Quantity
            HStack {
                Text("quantity")
                    .font(.mono(11)).foregroundStyle(c.muted)
                    .tracking(1).textCase(.uppercase)
                Spacer()
                HStack(spacing: 20) {
                    Button {
                        if state.orderState.quantity > 1 {
                            Haptics.impact(.light)
                            state.orderState.quantity -= 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(c.text)
                            .frame(width: 32, height: 32)
                            .background(c.card)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    }
                    Text("\(order.quantity)")
                        .font(.mono(18, weight: .medium))
                        .foregroundStyle(c.text)
                        .frame(minWidth: 24, alignment: .center)
                    Button {
                        if state.orderState.quantity < 24 {
                            Haptics.impact(.light)
                            state.orderState.quantity += 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(c.text)
                            .frame(width: 32, height: 32)
                            .background(c.card)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    }
                }
            }
            .padding(Spacing.md)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

            if let error {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.mono(11)).foregroundStyle(Color.fraiseRed)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        self.error = nil
                        Task { await preparePayment() }
                    } label: {
                        Text("retry")
                            .font(.mono(10)).foregroundStyle(c.muted)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(c.searchBg).clipShape(Capsule())
                    }
                }
            }

            // Total + pay
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("total")
                        .font(.mono(11)).foregroundStyle(c.muted)
                        .tracking(1).textCase(.uppercase)
                    Spacer()
                    Text(String(format: "CA$%.2f", Double(order.totalCents) / 100))
                        .font(.system(size: 22, design: .serif))
                        .foregroundStyle(c.text)
                }

                if let sheet = paymentSheet {
                    PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                        handlePaymentResult(result)
                    } label: { payButtonLabel }
                } else {
                    Button {
                        guard state.isSignedIn else { state.panel = .auth; return }
                        Task { await preparePayment() }
                    } label: { payButtonLabel }
                    .disabled(loading)
                }
            }
        }
    }

    private var payButtonLabel: some View {
        HStack {
            if loading { ProgressView().tint(.white) }
            Text(loading ? "—" : "pay")
                .font(.mono(14, weight: .medium)).foregroundStyle(.white)
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
        .background(c.text)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Confirmed

    private var confirmedStep: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Checkmark
            ZStack {
                Circle().fill(c.text).frame(width: 52, height: 52)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(c.background)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("confirmed")
                    .font(.system(size: 28, design: .serif))
                    .foregroundStyle(c.text)
                if let confirmed = state.confirmedOrder {
                    Text(confirmed.varietyName?.lowercased() ?? "your order")
                        .font(.mono(13)).foregroundStyle(c.muted)
                }
            }

            Text("you'll receive a notification when your box is ready.")
                .font(.mono(12)).foregroundStyle(c.muted).lineSpacing(4)

            if let date = state.confirmedOrder?.deliveryDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10)).foregroundStyle(Color.fraiseGreen)
                    Text("delivery \(date)")
                        .font(.mono(10)).foregroundStyle(Color.fraiseGreen)
                }
            }

            if let confirmed = state.confirmedOrder,
               let queued = confirmed.queuedBoxes,
               let minQ = confirmed.minQuantity, minQ > 0 {
                let pct = min(1.0, Double(queued) / Double(minQ))
                let remaining = max(0, minQ - queued)
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(c.searchBg).frame(height: 4)
                            Capsule()
                                .fill(pct >= 1.0 ? Color.fraiseGreen : c.text)
                                .frame(width: geo.size.width * pct, height: 4)
                                .animation(.spring(response: 0.6), value: pct)
                        }
                    }
                    .frame(height: 4)
                    if remaining > 0 {
                        Text("\(remaining) more order\(remaining == 1 ? "" : "s") until this batch ships")
                            .font(.mono(10)).foregroundStyle(c.muted)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(Color.fraiseGreen)
                            Text("threshold met — delivery confirmed")
                                .font(.mono(10)).foregroundStyle(Color.fraiseGreen)
                        }
                    }
                }
                .padding(Spacing.md)
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
            }

            Spacer(minLength: 24)

            Button {
                state.confirmedOrder = nil
                state.orderState.reset()
            } label: {
                Text("order again")
                    .font(.mono(13)).foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Row helpers

    private func selectionRow(title: String, subtitle: String, trailing: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mono(14)).foregroundStyle(c.text)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.mono(11)).foregroundStyle(c.muted).lineLimit(2)
                    }
                }
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing).font(.mono(13)).foregroundStyle(c.muted)
                }
                ZStack {
                    Circle().fill(selected ? c.text : Color.clear).frame(width: 20, height: 20)
                    Circle().strokeBorder(selected ? c.text : c.border, lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(Spacing.md)
            .background(selected ? c.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? c.border : c.border.opacity(0.5), lineWidth: 0.5))
        }
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mono(11)).foregroundStyle(c.muted)
                .tracking(1).textCase(.uppercase)
            Spacer()
            Text(value.lowercased()).font(.mono(13)).foregroundStyle(c.text)
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

        loading = true; error = nil
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
            pendingOrderId = response.id
            paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func handlePaymentResult(_ result: PaymentSheetResult) {
        paymentSheet = nil
        switch result {
        case .canceled:
            break
        case .failed(let e):
            Haptics.notification(.error)
            error = e.localizedDescription
        case .completed:
            Haptics.notification(.success)
            goingForward = true
            let orderId = pendingOrderId ?? 0
            let varietyName = order.varietyName
            let locationName = state.activeLocation?.name ?? ""
            state.confirmedOrder = ConfirmedOrder(
                id: orderId, status: "paid", varietyName: varietyName,
                queuedBoxes: nil, minQuantity: nil, deliveryDate: nil
            )
            if #available(iOS 16.2, *) {
                startOrderLiveActivity(orderId: orderId, varietyName: varietyName ?? "order", locationName: locationName)
            }
            if orderId > 0, let token = Keychain.userToken {
                Task { @MainActor in
                    if let confirmed = try? await APIClient.shared.confirmOrder(orderId: orderId, token: token) {
                        state.confirmedOrder = ConfirmedOrder(
                            id: confirmed.id, status: confirmed.status,
                            varietyName: confirmed.varietyName ?? varietyName,
                            queuedBoxes: confirmed.queuedBoxes,
                            minQuantity: confirmed.minQuantity,
                            deliveryDate: confirmed.deliveryDate
                        )
                    }
                }
            }
        }
    }
}
