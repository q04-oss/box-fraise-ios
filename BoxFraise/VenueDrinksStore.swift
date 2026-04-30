import SwiftUI

// VenueDrinksStore owns the menu and cart for a single business.
// Cart state is persisted to UserDefaults keyed by business ID so it
// survives sheet dismissal and app backgrounding.
@Observable
@MainActor
final class VenueDrinksStore {
    let business: Business

    var menu:        [VenueDrink] = []
    var isLoading    = false
    var error:       String?

    // Cart — quantities keyed by drink ID. Persisted across sheet dismissals.
    private(set) var cart: [Int: Int] = [:]  // drinkId → qty

    // Last submitted order — shown in confirmation UI.
    var pendingClientSecret: String?
    var pendingOrderId:      Int?
    var isSubmittingOrder    = false
    var orderError:          String?

    // CartItems derived from menu + cart for display.
    var cartItems: [CartItem] {
        menu.compactMap { drink in
            guard let qty = cart[drink.id], qty > 0 else { return nil }
            return CartItem(id: drink.id, name: drink.name, price: drink.priceCents, qty: qty)
        }
    }

    var cartTotalCents: Int { cartItems.reduce(0) { $0 + $1.price * $1.qty } }
    var cartCount:      Int { cart.values.reduce(0, +) }

    private let defaultsKey: String

    init(business: Business) {
        self.business  = business
        self.defaultsKey = "cart-\(business.id)"
        self.cart = loadCart()
    }

    // MARK: - Menu

    func loadMenu() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            menu = try await APIClient.shared.fetchVenueDrinks(businessId: business.id)
            applyLastOrderDefaults()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Cart mutations (optimistic)

    func add(_ drink: VenueDrink) {
        cart[drink.id, default: 0] += 1
        saveCart()
    }

    func remove(_ drink: VenueDrink) {
        guard let qty = cart[drink.id], qty > 0 else { return }
        if qty == 1 { cart.removeValue(forKey: drink.id) }
        else        { cart[drink.id] = qty - 1 }
        saveCart()
    }

    func clearCart() {
        cart.removeAll()
        saveCart()
    }

    // MARK: - Order submission

    func submitOrder(token: FraiseToken) async {
        guard !cartItems.isEmpty, !isSubmittingOrder else { return }
        isSubmittingOrder = true
        orderError = nil
        let snapshot = cartItems   // capture before clearing
        let idempotencyKey = UUID().uuidString

        do {
            let response = try await APIClient.shared.createVenueOrder(
                businessId:     business.id,
                items:          snapshot.map { (drinkId: $0.id, quantity: $0.qty) },
                idempotencyKey: idempotencyKey,
                notes:          nil,
                token:          token
            )
            pendingClientSecret = response.clientSecret
            pendingOrderId      = response.orderId
            saveLastOrder(snapshot)
        } catch {
            orderError = error.localizedDescription
            // Rollback is implicit — cart was never cleared. The user can retry.
        }
        isSubmittingOrder = false
    }

    func clearPendingOrder() {
        pendingClientSecret = nil
        pendingOrderId      = nil
    }

    // MARK: - Persistence

    private func saveCart() {
        let encoded = cart.reduce(into: [String: Int]()) { $0["\($1.key)"] = $1.value }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }

    private func loadCart() -> [Int: Int] {
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int]
        else { return [:] }
        return raw.reduce(into: [:]) { if let k = Int($1.key) { $0[k] = $1.value } }
    }

    // Pre-fill cart with the last order at this business.
    private func applyLastOrderDefaults() {
        let lastKey = "last-order-\(business.id)"
        guard cart.isEmpty,
              let raw = UserDefaults.standard.dictionary(forKey: lastKey) as? [String: Int]
        else { return }
        cart = raw.reduce(into: [:]) { if let k = Int($1.key) { $0[k] = $1.value } }
        saveCart()
    }

    private func saveLastOrder(_ items: [CartItem]) {
        let lastKey = "last-order-\(business.id)"
        let encoded = items.reduce(into: [String: Int]()) { $0["\($1.id)"] = $1.qty }
        UserDefaults.standard.set(encoded, forKey: lastKey)
    }
}
