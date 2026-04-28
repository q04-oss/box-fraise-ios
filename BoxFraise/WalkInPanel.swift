import SwiftUI
import StripePaymentSheet

struct WalkInPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var nfcToken = ""
    @State private var selectedItem: WalkInItem?
    @State private var chocolate = "dark"
    @State private var finish = "plain"
    @State private var customerEmail = ""
    @State private var paymentSheet: PaymentSheet?
    @State private var loading = false
    @State private var error: String?
    @State private var confirmed = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FraiseBackButton { state.panel = state.isSignedIn ? .staff : .home }
                Spacer()
                Text("walk-in")
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if confirmed {
                confirmedView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // NFC token
                        VStack(alignment: .leading, spacing: 6) {
                            FraiseSectionLabel(text: "box token")
                            TextField("scan or enter token", text: $nfcToken)
                                .font(.mono(14))
                                .foregroundStyle(c.text)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(c.searchBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
                        }

                        // Inventory list
                        if !state.walkInInventory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                FraiseSectionLabel(text: "variety")
                                ForEach(state.walkInInventory) { item in
                                    Button { selectedItem = item } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.name.lowercased())
                                                    .font(.mono(14))
                                                    .foregroundStyle(c.text)
                                                if let stock = item.stockRemaining {
                                                    Text("\(stock) remaining")
                                                        .font(.mono(10))
                                                        .foregroundStyle(c.muted)
                                                }
                                            }
                                            Spacer()
                                            Text(item.priceFormatted)
                                                .font(.mono(13))
                                                .foregroundStyle(c.muted)
                                            ZStack {
                                                Circle().fill(selectedItem?.id == item.id ? c.text : Color.clear).frame(width: 20, height: 20)
                                                Circle().strokeBorder(selectedItem?.id == item.id ? c.text : c.border, lineWidth: 1.5).frame(width: 20, height: 20)
                                                if selectedItem?.id == item.id {
                                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                                }
                                            }
                                        }
                                        .padding(Spacing.md)
                                        .background(selectedItem?.id == item.id ? c.card : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selectedItem?.id == item.id ? c.border : c.border.opacity(0.5), lineWidth: 0.5))
                                    }
                                }
                            }
                        }

                        // Chocolate
                        VStack(alignment: .leading, spacing: 8) {
                            FraiseSectionLabel(text: "chocolate")
                            ForEach(CHOCOLATES, id: \.id) { opt in
                                Button { chocolate = opt.id } label: {
                                    HStack {
                                        Text(opt.name.lowercased()).font(.mono(14)).foregroundStyle(c.text)
                                        Spacer()
                                        ZStack {
                                            Circle().fill(chocolate == opt.id ? c.text : Color.clear).frame(width: 20, height: 20)
                                            Circle().strokeBorder(chocolate == opt.id ? c.text : c.border, lineWidth: 1.5).frame(width: 20, height: 20)
                                            if chocolate == opt.id { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(chocolate == opt.id ? c.card : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border.opacity(0.5), lineWidth: 0.5))
                                }
                            }
                        }

                        // Finish
                        VStack(alignment: .leading, spacing: 8) {
                            FraiseSectionLabel(text: "finish")
                            ForEach(FINISHES, id: \.id) { opt in
                                Button { finish = opt.id } label: {
                                    HStack {
                                        Text(opt.name.lowercased()).font(.mono(14)).foregroundStyle(c.text)
                                        Spacer()
                                        ZStack {
                                            Circle().fill(finish == opt.id ? c.text : Color.clear).frame(width: 20, height: 20)
                                            Circle().strokeBorder(finish == opt.id ? c.text : c.border, lineWidth: 1.5).frame(width: 20, height: 20)
                                            if finish == opt.id { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(finish == opt.id ? c.card : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border.opacity(0.5), lineWidth: 0.5))
                                }
                            }
                        }

                        // Customer email
                        VStack(alignment: .leading, spacing: 6) {
                            FraiseSectionLabel(text: "customer email")
                            TextField("optional", text: $customerEmail)
                                .font(.mono(14))
                                .foregroundStyle(c.text)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(c.searchBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
                        }

                        if let error {
                            Text(error)
                                .font(.mono(11))
                                .foregroundStyle(Color(hex: "C0392B"))
                        }

                        if let sheet = paymentSheet {
                            PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                                handlePayment(result)
                            } label: {
                                payLabel
                            }
                        } else {
                            Button {
                                Task { await prepare() }
                            } label: {
                                payLabel
                            }
                            .disabled(loading || nfcToken.isEmpty || selectedItem == nil)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .task {
            if let loc = state.activeLocation {
                state.walkInInventory = (try? await APIClient.shared.fetchWalkInInventory(locationId: loc.id)) ?? []
            }
        }
    }

    private var payLabel: some View {
        HStack {
            if loading { ProgressView().tint(.white) }
            Text(loading ? "—" : "charge →")
                .font(.mono(13, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(nfcToken.isEmpty ? c.muted : c.text)
        .clipShape(Capsule())
    }

    private var confirmedView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ZStack {
                Circle().fill(c.text).frame(width: 52, height: 52)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(c.background)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("sold")
                    .font(.system(size: 28, design: .serif))
                    .foregroundStyle(c.text)
                if let item = selectedItem {
                    Text(item.name.lowercased())
                        .font(.mono(13)).foregroundStyle(c.muted)
                }
                Text([chocolate, finish]
                    .map { $0.replacingOccurrences(of: "_", with: " ") }
                    .joined(separator: " · ").lowercased())
                    .font(.mono(11)).foregroundStyle(c.muted)
            }

            Spacer(minLength: 24)

            Button {
                confirmed = false
                nfcToken = ""; selectedItem = nil
                customerEmail = ""; paymentSheet = nil; error = nil
            } label: {
                HStack {
                    Text("next customer")
                        .font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(c.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    @MainActor private func prepare() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let response = try await APIClient.shared.createWalkInOrder(
                nfcToken: nfcToken,
                chocolate: chocolate,
                finish: finish,
                customerEmail: customerEmail.isEmpty ? "walkin@fraise.box" : customerEmail
            )
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "Box Fraise"
            config.applePay = .init(merchantId: "merchant.com.boxfraise.app", merchantCountryCode: "CA")
            paymentSheet = PaymentSheet(paymentIntentClientSecret: response.clientSecret, configuration: config)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func handlePayment(_ result: PaymentSheetResult) {
        paymentSheet = nil
        switch result {
        case .completed:
            Haptics.notification(.success)
            confirmed = true
        case .failed(let e):
            Haptics.notification(.error)
            error = e.localizedDescription
        case .canceled: break
        }
    }
}
