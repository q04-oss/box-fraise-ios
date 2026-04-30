import Foundation

extension APIClient {

    func fetchVenueDrinks(businessId: Int) async throws -> [VenueDrink] {
        try await request("/businesses/\(businessId)/drinks")
    }

    func createVenueOrder(
        businessId:     Int,
        items:          [(drinkId: Int, quantity: Int)],
        idempotencyKey: String,
        notes:          String?,
        token:          FraiseToken
    ) async throws -> VenueOrderResponse {
        let body: [String: Any] = [
            "business_id":     businessId,
            "idempotency_key": idempotencyKey,
            "items":           items.map { ["drink_id": $0.drinkId, "quantity": $0.quantity] },
            "notes":           notes as Any
        ]
        return try await request("/venue-orders", method: "POST", body: body, token: token)
    }
}
