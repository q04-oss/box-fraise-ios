import SwiftUI
import StripePaymentSheet

struct VenueDrinksPanel: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    let business: Business
    @State private var store: VenueDrinksStore
    @State private var paymentSheet: PaymentSheet?
    @State private var showCart = false

    init(business: Business) {
        self.business = business
        _store = State(initialValue: VenueDrinksStore(business: business))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────────
            HStack {
                FraiseBackButton { state.navigate(to: .partnerDetail(business)) }
                Spacer()
                if store.cartCount > 0 {
                    Button {
                        showCart = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(store.cartCount)")
                                .font(.mono(12))
                                .foregroundStyle(c.text)
                            Text(store.cartTotalCents.formattedPrice)
                                .font(.mono(12))
                                .foregroundStyle(c.muted)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(c.card)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(c.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 12)
            .animation(.fraiseSpring, value: store.cartCount > 0)

            Divider().opacity(Divide.section)

            // ── Menu ───────────────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("menu")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5).textCase(.uppercase)
                        Text(business.name.lowercased())
                            .font(.system(size: 24, design: .serif)).foregroundStyle(c.text)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)

                    if store.isLoading {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(height: 64)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, 4)
                        }
                    } else if store.menu.isEmpty {
                        Text("no drinks available")
                            .font(.mono(13)).foregroundStyle(c.muted)
                            .padding(Spacing.md)
                    } else {
                        ForEach(store.menu) { drink in
                            DrinkRow(drink: drink, qty: store.cart[drink.id] ?? 0) { delta in
                                if delta > 0 { store.add(drink) }
                                else         { store.remove(drink) }
                            }
                            Divider().padding(.leading, Spacing.md).opacity(Divide.row)
                        }
                    }
                }
                .padding(.bottom, store.cartCount > 0 ? 100 : 32)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showCart) {
            CartSheet(business: business, store: store)
        }
        .onAppear { Task { await store.loadMenu() } }
    }
}

// MARK: - Drink row

private struct DrinkRow: View {
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

            // Stepper
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

// MARK: - Cart sheet

struct CartSheet: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss)       private var dismiss
    let business: Business
    @Bindable var store: VenueDrinksStore  // @Bindable because VenueDrinksStore is @Observable
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

                // Payment button
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
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button("clear") {
                    store.clearCart()
                    dismiss()
                }
                .font(.mono(12)).foregroundStyle(c.muted)
            }}
        }
        .fraiseTheme()
    }

    private var payButtonLabel: some View {
        Group {
            if store.isSubmittingOrder {
                ProgressView()
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
                    .background(c.text)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
            } else {
                Text("pay \(store.cartTotalCents.formattedPrice)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(c.background)
                    .frame(height: 48)
                    .frame(maxWidth: .infinity)
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
            // Haptic confirmation
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
            // Nudge the user back to the business detail so they see the loyalty update.
            state.navigate(to: .partnerDetail(business))
        case .canceled:
            break
        case .failed(let err):
            store.orderError = err.localizedDescription
        }
    }
}

// MARK: - Helpers

private extension Int {
    var formattedPrice: String {
        String(format: "$%.2f", Double(self) / 100)
    }
}
