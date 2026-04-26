import SwiftUI
import StripePaymentSheet

struct CreditsView: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.dismiss) var dismiss

    @State private var credits      = 1
    @State private var loading      = false
    @State private var error: String? = nil
    @State private var paymentSheet: PaymentSheet? = nil
    @State private var pendingIntentId: String? = nil

    private let creditPrice = 120 // CA$120

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {

                    FraiseCard {
                        StatRow(label: "price per credit", value: "CA$\(creditPrice)", topBorder: false)
                        StatRow(label: "current balance",  value: "\(appState.member?.creditBalance ?? 0) credits")
                        StatRow(label: "purchasing",       value: "\(credits) credit\(credits == 1 ? "" : "s")")
                        StatRow(label: "total",            value: "CA$\(credits * creditPrice)")
                    }

                    // Quantity stepper
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionLabel(text: "quantity")
                        HStack(spacing: Spacing.md) {
                            Button {
                                if credits > 1 { credits -= 1 }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.mono(14))
                                    .foregroundStyle(c.text)
                                    .frame(width: 44, height: 44)
                                    .background(c.card)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(c.border, lineWidth: 0.5))
                            }

                            Text("\(credits)")
                                .font(.mono(18, weight: .medium))
                                .foregroundStyle(c.text)
                                .frame(minWidth: 40, alignment: .center)

                            Button {
                                if credits < 10 { credits += 1 }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.mono(14))
                                    .foregroundStyle(c.text)
                                    .frame(width: 44, height: 44)
                                    .background(c.card)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(c.border, lineWidth: 0.5))
                            }
                        }
                    }

                    if let error { ErrorText(message: error) }

                    if let sheet = paymentSheet {
                        PaymentSheet.PaymentButton(
                            paymentSheet: sheet,
                            onCompletion: handlePaymentResult
                        ) {
                            PrimaryButtonLabel(label: "pay CA$\(credits * creditPrice) →")
                        }
                    } else {
                        PrimaryButton(label: "continue →", loading: loading) {
                            Task { await prepareCheckout() }
                        }
                    }

                    Text("one credit = CA$\(creditPrice). no subscription, no expiry. returned automatically if an event doesn't go ahead.")
                        .font(.mono(11))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                }
                .padding(Spacing.lg)
            }
            .background(c.background)
            .fraiseNav("buy credits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                }
            }
        }
    }

    // MARK: - Checkout

    private func prepareCheckout() async {
        guard let token = Keychain.memberToken else { return }
        loading = true; error = nil; paymentSheet = nil

        do {
            let checkout = try await APIClient.shared.creditsCheckout(credits: credits, token: token)
            pendingIntentId = extractPaymentIntentId(from: checkout.clientSecret)

            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "box fraise"
            config.applePay = .init(
                merchantId: "merchant.com.boxfraise.app",
                merchantCountryCode: "CA"
            )
            config.primaryButtonLabel = "pay CA$\(credits * creditPrice)"
            config.allowsDelayedPaymentMethods = false

            paymentSheet = PaymentSheet(
                paymentIntentClientSecret: checkout.clientSecret,
                configuration: config
            )
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .canceled:
            paymentSheet = nil

        case .failed(let err):
            error = err.localizedDescription
            paymentSheet = nil

        case .completed:
            Task { await confirmCredits() }
        }
    }

    private func confirmCredits() async {
        guard let token = Keychain.memberToken,
              let intentId = pendingIntentId else { return }
        loading = true
        do {
            try await APIClient.shared.creditsConfirm(paymentIntentId: intentId, token: token)
            await appState.refreshMe()
            dismiss()
        } catch {
            // Webhook will handle it server-side if this fails
            await appState.refreshMe()
            dismiss()
        }
        loading = false
    }

    private func extractPaymentIntentId(from clientSecret: String) -> String {
        String(clientSecret.split(separator: "_secret_").first ?? "")
    }
}
