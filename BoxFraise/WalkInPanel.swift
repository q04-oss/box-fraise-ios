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
                Button { state.panel = state.isSignedIn ? .staff : .home } label: {
                    Text("← back")
                        .font(.mono(12))
                        .foregroundStyle(c.muted)
                }
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
                            sectionLabel("box token")
                            TextField("scan or enter token", text: $nfcToken)
                                .font(.mono(14))
                                .foregroundStyle(c.text)
                                .autocapitalization(.none)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(c.searchBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
                        }

                        // Inventory list
                        if !state.walkInInventory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                sectionLabel("variety")
                                ForEach(state.walkInInventory) { item in
                                    Button {
                                        selectedItem = item
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name)
                                                    .font(.mono(13))
                                                    .foregroundStyle(c.text)
                                                if let stock = item.stockRemaining {
                                                    Text("\(stock) remaining")
                                                        .font(.mono(10))
                                                        .foregroundStyle(c.muted)
                                                }
                                            }
                                            Spacer()
                                            Text(item.priceFormatted)
                                                .font(.mono(12))
                                                .foregroundStyle(c.muted)
                                            Circle()
                                                .strokeBorder(selectedItem?.id == item.id ? c.text : c.border,
                                                              lineWidth: selectedItem?.id == item.id ? 5 : 1)
                                                .frame(width: 18, height: 18)
                                        }
                                        .padding(Spacing.md)
                                        .background(selectedItem?.id == item.id ? c.card : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
                                    }
                                }
                            }
                        }

                        // Chocolate + finish
                        pickerRow("chocolate", options: CHOCOLATES, selected: $chocolate)
                        pickerRow("finish",    options: FINISHES,    selected: $finish)

                        // Customer email
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("customer email")
                            TextField("optional", text: $customerEmail)
                                .font(.mono(14))
                                .foregroundStyle(c.text)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
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
                            .disabled(loading || nfcToken.isEmpty)
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("sold")
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(c.text)
            if let item = selectedItem {
                Text(item.name.lowercased())
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }
            Button {
                confirmed = false
                nfcToken = ""
                selectedItem = nil
                customerEmail = ""
                paymentSheet = nil
            } label: {
                Text("next customer")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .font(.mono(9))
            .foregroundStyle(c.muted)
            .tracking(1.5)
            .textCase(.uppercase)
    }

    private func pickerRow(_ label: String, options: [(id: String, name: String)], selected: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(label)
            HStack(spacing: 8) {
                ForEach(options, id: \.id) { opt in
                    Button {
                        selected.wrappedValue = opt.id
                    } label: {
                        Text(opt.name)
                            .font(.mono(11))
                            .foregroundStyle(selected.wrappedValue == opt.id ? c.background : c.muted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected.wrappedValue == opt.id ? c.text : c.searchBg)
                            .clipShape(Capsule())
                    }
                }
            }
        }
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

    private func handlePayment(_ result: PaymentSheetResult) {
        DispatchQueue.main.async {
            self.paymentSheet = nil
            switch result {
            case .completed: self.confirmed = true
            case .failed(let e): self.error = e.localizedDescription
            case .canceled: break
            }
        }
    }
}
