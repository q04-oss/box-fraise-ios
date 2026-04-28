import Foundation

extension APIClient {

    // MARK: - Orders

    func createOrder(locationId: Int, varietyId: Int, chocolate: String, finish: String,
                     quantity: Int, token: FraiseToken) async throws -> OrderResponse {
        try await request("/orders", method: "POST", body: [
            "location_id": locationId,
            "variety_id":  varietyId,
            "chocolate":   chocolate,
            "finish":      finish,
            "quantity":    quantity,
        ], token: token)
    }

    func confirmOrder(orderId: Int, token: FraiseToken) async throws -> ConfirmedOrder {
        try await request("/orders/\(orderId)/confirm", method: "POST", body: [:], token: token)
    }

    func payWithBalance(orderId: Int, token: FraiseToken) async throws -> ConfirmedOrder {
        try await request("/orders/\(orderId)/pay-balance", method: "POST", token: token)
    }

    func fetchOrderHistory(token: FraiseToken) async throws -> [PastOrder] {
        try await request("/users/me/orders", token: token)
    }

    func fetchOrderReceipt(orderId: Int, token: FraiseToken) async throws -> OrderReceipt {
        try await request("/orders/\(orderId)/receipt", token: token)
    }

    func rateOrder(id: Int, rating: Int, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/orders/\(id)/rate", method: "POST",
                                               body: ["rating": rating], token: token)
    }

    // MARK: - Standing orders

    func fetchStandingOrders(token: FraiseToken) async throws -> [StandingOrder] {
        try await request("/users/me/standing-orders", token: token)
    }

    func createStandingOrder(varietyId: Int, locationId: Int, quantity: Int,
                             chocolate: String, finish: String, token: FraiseToken) async throws -> StandingOrder {
        try await request("/users/me/standing-orders", method: "POST", body: [
            "variety_id":  varietyId,
            "location_id": locationId,
            "quantity":    quantity,
            "chocolate":   chocolate,
            "finish":      finish,
        ], token: token)
    }

    func updateStandingOrder(id: Int, status: String, token: FraiseToken) async throws {
        let _: OKResponse = try await request("/users/me/standing-orders/\(id)", method: "PATCH",
                                               body: ["status": status], token: token)
    }
}
