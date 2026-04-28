import SwiftUI
import StripePaymentSheet

// MARK: - App Clip
// Add this file to the App Clip target in Xcode.
// Bundle ID: com.boxfraise.app.Clip
// Triggered by NFC tap or QR code: https://fraise.box/clip?location=<slug>
//
// The App Clip target needs its own entitlements file with:
//   com.apple.developer.parent-application-identifiers = ["$(AppIdentifierPrefix)com.boxfraise.app"]
//   com.apple.developer.associated-domains = ["appclips:fraise.box"]
//   com.apple.developer.in-app-payments = ["merchant.com.boxfraise.app"]

@main
struct BoxFraiseClipApp: App {
    var body: some Scene {
        WindowGroup {
            AppClipContentView()
                .fraiseTheme()
        }
    }
}

struct AppClipContentView: View {
    @State private var locationSlug = ""
    @State private var varieties: [Variety] = []
    @State private var selected: Variety?
    @State private var paymentSheet: PaymentSheet?
    @State private var loading = false
    @State private var confirmed = false
    @State private var error: String?
    @Environment(\.fraiseColors) private var c

    var body: some View {
        Group {
            if confirmed { confirmedView } else { orderView }
        }
        .onContinueUserActivity(NSUserActivityTypes.first ?? NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let slug = components.queryItems?.first(where: { $0.name == "location" })?.value
            else { return }
            locationSlug = slug
            Task { await loadVarieties() }
        }
    }

    // MARK: - Order view

    private var orderView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("🍓").font(.system(size: 28))
                Text("box fraise")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(c.text)
            }

            FraiseSectionLabel(text: "pick your strawberry")

            if loading {
                ProgressView().tint(c.muted)
            } else if varieties.isEmpty {
                Text("no varieties available right now")
                    .font(.mono(13)).foregroundStyle(c.muted)
            } else {
                ForEach(varieties) { v in
                    Button { selected = v } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(v.name.lowercased())
                                    .font(.mono(14)).foregroundStyle(c.text)
                                Text(v.priceFormatted)
                                    .font(.mono(11)).foregroundStyle(c.muted)
                            }
                            Spacer()
                            Circle()
                                .strokeBorder(
                                    selected?.id == v.id ? c.text : c.border,
                                    lineWidth: selected?.id == v.id ? 5 : 1
                                )
                                .frame(width: 18, height: 18)
                        }
                        .padding(Spacing.md)
                        .background(selected?.id == v.id ? c.card : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border.opacity(0.5), lineWidth: 0.5))
                    }
                }
            }

            if let error {
                Text(error).font(.mono(11)).foregroundStyle(Color(hex: "C0392B"))
            }

            Spacer()

            if let sheet = paymentSheet {
                PaymentSheet.PaymentButton(paymentSheet: sheet) { result in
                    handlePayment(result)
                } label: { payButton }
            } else {
                Button {
                    guard selected != nil else { self.error = "select a variety first"; return }
                    Task { await prepare() }
                } label: { payButton }
                    .disabled(loading || selected == nil)
            }

            Text("get box fraise for order history, popups & more")
                .font(.mono(9)).foregroundStyle(c.muted).tracking(0.5)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
    }

    // MARK: - Confirmed view

    private var confirmedView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("confirmed")
                .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)
            Text("you'll receive a notification when your box is ready.")
                .font(.mono(12)).foregroundStyle(c.muted).lineSpacing(4)
            Spacer()
            Link(destination: URL(string: "https://apps.apple.com/app/box-fraise")!) {
                Text("get box fraise →")
                    .font(.mono(12, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(c.text).clipShape(Capsule())
            }
        }
        .padding(Spacing.md)
    }

    private var payButton: some View {
        HStack {
            if loading { ProgressView().tint(.white) }
            Text(loading ? "—" : "pay  →")
                .font(.mono(14, weight: .medium)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(c.text).clipShape(Capsule())
    }

    // MARK: - Networking

    private func loadVarieties() async {
        loading = true; defer { loading = false }
        guard let url = URL(string: "https://fraise.box/api/varieties"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let varieties = try? JSONDecoder().decode([Variety].self, from: data)
        else { return }
        self.varieties = varieties.filter { $0.active ?? true }
    }

    private func prepare() async {
        guard let v = selected else { return }
        loading = true; error = nil; defer { loading = false }
        do {
            guard let url = URL(string: "https://fraise.box/api/orders/clip") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: [
                "location_slug": locationSlug,
                "variety_id": v.id,
                "quantity": 1,
            ])
            let (data, _) = try await URLSession.shared.data(for: req)
            let response = try JSONDecoder().decode(OrderResponse.self, from: data)

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
        case .completed: confirmed = true
        case .failed(let e): error = e.localizedDescription
        case .canceled: break
        }
    }
}
