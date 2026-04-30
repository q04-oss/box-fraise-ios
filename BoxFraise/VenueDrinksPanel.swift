import SwiftUI
import StripePaymentSheet

// MARK: - Drink row (used inline in PartnerDetailPanel)

struct DrinkRow: View {
    @Environment(\.fraiseColors) private var c
    let drink:    VenueDrink
    let qty:      Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(drink.name.lowercased())
                    .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                if !drink.description.isEmpty {
                    Text(drink.description.lowercased())
                        .font(.mono(11)).foregroundStyle(c.muted).lineLimit(1)
                }
            }
            Spacer()
            Text(drink.formattedPrice)
                .font(.mono(12)).foregroundStyle(c.muted)

            HStack(spacing: 0) {
                if qty > 0 {
                    Button { onChange(-1) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(c.text)
                    }
                    .transition(.scale.combined(with: .opacity))

                    Text("\(qty)")
                        .font(.mono(13)).foregroundStyle(c.text)
                        .frame(width: 20)
                        .transition(.opacity)
                }
                Button { onChange(1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(c.text)
                }
            }
            .animation(.fraiseSpring, value: qty)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
    }
}

// MARK: - Cart sheet (presented from PartnerDetailPanel)

struct CartSheet: View {
    @Environment(AppState.self)   private var state
    @Environment(\.fraiseColors)  private var c
    @Environment(\.dismiss)       private var dismiss
    let business: Business
    let store:    VenueDrinksStore
    @State private var paymentSheet: PaymentSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(store.cartItems) { item in
                        HStack {
                            Text(item.name.lowercased())
                                .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                            Spacer()
                            Text("×\(item.qty)")
                                .font(.mono(12)).foregroundStyle(c.muted)
                            Text((item.price * item.qty).formattedPrice)
                                .font(.mono(12)).foregroundStyle(c.text)
                        }
                    }

                    HStack {
                        Text("total")
                            .font(.mono(12)).foregroundStyle(c.muted)
                        Spacer()
                        Text(store.cartTotalCents.formattedPrice)
                            .font(.mono(13)).foregroundStyle(c.text)
                    }
                    .listRowBackground(c.card)
                }
                .listStyle(.plain)

                if let err = store.orderError {
                    Text(err).font(.mono(11)).foregroundStyle(.red)
                        .padding(.horizontal, Spacing.md).padding(.top, 8)
                }

                Group {
                    if let sheet = paymentSheet {
                        PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                            handlePaymentResult(result)
                        } label: {
                            payButtonLabel
                        }
                    } else {
                        Button {
                            guard let token = state.user?.token else { return }
                            Task { await preparePayment(token: token) }
                        } label: {
                            payButtonLabel
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isSubmittingOrder || store.cartItems.isEmpty)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 32)
                .padding(.top, 12)
            }
            .navigationTitle("your order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("clear") {
                        store.clearCart()
                        dismiss()
                    }
                    .font(.mono(12)).foregroundStyle(c.muted)
                }
            }
        }
        .fraiseTheme()
    }

    private var payButtonLabel: some View {
        Group {
            if store.isSubmittingOrder {
                ProgressView()
                    .frame(height: 48).frame(maxWidth: .infinity)
                    .background(c.text)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            } else {
                Text("pay \(store.cartTotalCents.formattedPrice)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(c.background)
                    .frame(height: 48).frame(maxWidth: .infinity)
                    .background(c.text)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            }
        }
    }

    private func preparePayment(token: FraiseToken) async {
        await store.submitOrder(token: token)
        guard let secret = store.pendingClientSecret else { return }
        var config = PaymentSheet.Configuration()
        config.merchantDisplayName = business.name
        paymentSheet = PaymentSheet(paymentIntentClientSecret: secret, configuration: config)
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        paymentSheet = nil
        switch result {
        case .completed:
            store.clearCart()
            store.clearPendingOrder()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        case .canceled:
            break
        case .failed(let err):
            store.orderError = err.localizedDescription
        }
    }
}

// MARK: - Helpers

extension Int {
    var formattedPrice: String {
        String(format: "$%.2f", Double(self) / 100)
    }
}
