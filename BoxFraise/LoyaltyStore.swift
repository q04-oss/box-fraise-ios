import SwiftUI

// LoyaltyStore owns all loyalty state for a single business.
// One instance is created when the user views a business's detail panel;
// it lives for the lifetime of that panel.
@Observable
@MainActor
final class LoyaltyStore {
    let business: Business

    var balance:        LoyaltyBalance?
    var events:         [LoyaltyEvent] = []
    var qrToken:        LoyaltyQrToken?
    var isLoadingBalance = false
    var isLoadingQR      = false
    var error:           String?

    // Refresh timer handle — cancelled when the store is deallocated.
    private var refreshTask: Task<Void, Never>?

    init(business: Business) {
        self.business = business
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Balance

    func loadBalance(token: FraiseToken) async {
        guard !isLoadingBalance else { return }
        isLoadingBalance = true
        defer { isLoadingBalance = false }
        do {
            balance = try await APIClient.shared.fetchLoyaltyBalance(
                businessId: business.id, token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadHistory(token: FraiseToken) async {
        do {
            events = try await APIClient.shared.fetchLoyaltyHistory(
                businessId: business.id, token: token
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - QR token

    func loadQRToken(token: FraiseToken) async {
        guard !isLoadingQR else { return }
        isLoadingQR = true
        defer { isLoadingQR = false }
        do {
            let result = try await APIClient.shared.fetchQrToken(
                businessId: business.id, token: token
            )
            qrToken = result
            scheduleRefresh(expiresAt: result.expiresAt, userToken: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // Refresh 30 seconds before the token expires so the customer never shows
    // an expired QR to staff.
    private func scheduleRefresh(expiresAt: Date, userToken: FraiseToken) {
        refreshTask?.cancel()
        let refreshIn = max(0, expiresAt.timeIntervalSinceNow - 30)
        refreshTask = Task {
            try? await Task.sleep(for: .seconds(refreshIn))
            guard !Task.isCancelled else { return }
            await loadQRToken(token: userToken)
        }
    }

    // MARK: - Stamp URL

    // The URL encoded in the QR — openable by a phone camera (HTML stamp page)
    // or parseable by the Box Fraise staff app scanner.
    func stampURL(baseURL: String = "https://fraise.box") -> String? {
        guard let t = qrToken else { return nil }
        return "\(baseURL)/stamp?t=\(t.token)&b=\(business.id)"
    }

    // MARK: - Inline copy helpers

    var progressLine: String {
        guard let b = balance else { return "" }
        if b.rewardAvailable { return "reward available — show QR to redeem" }
        if b.steepsUntilReward == 1 { return "1 more steep until \(b.rewardDescription)" }
        return "\(b.steepsUntilReward) more steeps until \(b.rewardDescription)"
    }
}
