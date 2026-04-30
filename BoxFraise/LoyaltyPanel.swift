import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Inline loyalty prompt (embedded in PartnerDetailPanel)

struct LoyaltyInlineView: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    @State private var store: LoyaltyStore

    init(business: Business) {
        _store = State(initialValue: LoyaltyStore(business: business))
    }

    var body: some View {
        Group {
            if let token = state.user?.token {
                content(token: token)
            }
        }
        // Refresh balance whenever the view appears (foreground return).
        .onAppear {
            guard let token = state.user?.token else { return }
            Task { await store.loadBalance(token: token) }
        }
    }

    @ViewBuilder
    private func content(token: FraiseToken) -> some View {
        Button {
            state.navigate(to: .loyalty(store.business))
        } label: {
            HStack(spacing: 12) {
                // Progress ring
                ZStack {
                    Circle()
                        .stroke(c.border, lineWidth: 2)
                    if let b = store.balance {
                        let progress = Double(b.currentBalance % b.steepsPerReward) / Double(b.steepsPerReward)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(c.text, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    if store.isLoadingBalance {
                        ProgressView().scaleEffect(0.5)
                    } else {
                        Text("\(store.balance?.currentBalance ?? 0)")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(c.text)
                    }
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("loyalty")
                        .font(.mono(9))
                        .foregroundStyle(c.muted)
                        .tracking(1.5)
                        .textCase(.uppercase)
                    Text(store.progressLine.isEmpty ? "tap to view stamps" : store.progressLine)
                        .font(.mono(12))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(c.border)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 13)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(store.balance?.rewardAvailable == true ? c.text.opacity(0.3) : c.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full loyalty panel (pushed when user taps inline view)

struct LoyaltyPanel: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    let business: Business
    @State private var store: LoyaltyStore
    @State private var showHistory = false

    init(business: Business) {
        self.business = business
        _store = State(initialValue: LoyaltyStore(business: business))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FraiseBackButton { state.navigate(to: .partnerDetail(business)) }

                // ── Header ────────────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    Text("loyalty")
                        .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5).textCase(.uppercase)
                    Text(business.name.lowercased())
                        .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)
                }

                if let balance = store.balance {
                    balanceSection(balance)
                } else if store.isLoadingBalance {
                    SkeletonBlock(height: 120)
                }

                qrSection

                if !store.events.isEmpty {
                    historyPreview
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showHistory) {
            LoyaltyHistorySheet(business: business)
        }
        .onAppear {
            guard let token = state.user?.token else { return }
            Task {
                await store.loadBalance(token: token)
                await store.loadQRToken(token: token)
                await store.loadHistory(token: token)
            }
        }
    }

    // MARK: - Balance section

    private func balanceSection(_ b: LoyaltyBalance) -> some View {
        VStack(spacing: 16) {
            // Large steep count
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(b.currentBalance)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(c.text)
                Text(b.currentBalance == 1 ? "steep" : "steeps")
                    .font(.mono(14)).foregroundStyle(c.muted)
            }

            // Segmented progress bar
            let segments = b.steepsPerReward
            HStack(spacing: 4) {
                ForEach(0..<segments, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < (b.currentBalance % segments) ? c.text : c.border)
                        .frame(height: 4)
                }
            }

            // Progress line
            Text(store.progressLine)
                .font(.mono(12)).foregroundStyle(c.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if b.rewardAvailable {
                Text("reward available")
                    .font(.mono(11)).foregroundStyle(c.text)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(c.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(c.text.opacity(0.3), lineWidth: 0.5))
                    .sensoryFeedback(.success, trigger: b.rewardAvailable)
            }
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
    }

    // MARK: - QR code section

    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("stamp code")
                .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5).textCase(.uppercase)

            if store.balance?.emailVerified == false {
                // Unverified — show prompt instead of QR.
                verificationPrompt
            } else if store.isLoadingQR {
                SkeletonBlock(height: 180)
            } else if let url = store.stampURL() {
                VStack(spacing: 12) {
                    QRCodeView(content: url)
                        .frame(width: 180, height: 180)
                        .frame(maxWidth: .infinity)

                    if let exp = store.qrToken?.expiresAt {
                        ExpiryCountdown(expiresAt: exp)
                    }

                    Text("show this to staff to earn a steep")
                        .font(.mono(11)).foregroundStyle(c.muted)
                }
                .padding(Spacing.md)
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
            } else {
                Button {
                    guard let token = state.user?.token else { return }
                    Task { await store.loadQRToken(token: token) }
                } label: {
                    Text("generate stamp code")
                        .font(.mono(13)).foregroundStyle(c.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(c.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button).strokeBorder(c.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Verification prompt

    @State private var resendSent    = false
    @State private var resendLoading = false

    private var verificationPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 36)).foregroundStyle(c.muted)

            VStack(spacing: 6) {
                Text("verify your email")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(c.text)
                Text("check your inbox for a verification link to start earning steeps at walk-in visits")
                    .font(.mono(12)).foregroundStyle(c.muted)
                    .multilineTextAlignment(.center).lineSpacing(3)
            }

            if resendSent {
                Text("email sent")
                    .font(.mono(12)).foregroundStyle(c.muted)
            } else {
                Button {
                    guard let token = state.user?.token, !resendLoading else { return }
                    resendLoading = true
                    Task {
                        try? await APIClient.shared.resendVerificationEmail(token: token)
                        resendSent   = true
                        resendLoading = false
                    }
                } label: {
                    Group {
                        if resendLoading {
                            ProgressView().frame(height: 20)
                        } else {
                            Text("resend verification email")
                                .font(.mono(12)).foregroundStyle(c.text)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).strokeBorder(c.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(resendLoading)
            }

            Text("in-app purchases still earn steeps — verification is only needed for walk-in stamps")
                .font(.mono(10)).foregroundStyle(c.muted)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(Spacing.md)
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
        // Return here so the compiler can see this as part of qrSection.
        // The early return in qrSection uses AnyView — workaround:
        .frame(maxWidth: .infinity)
    }

    // MARK: - History preview

    private var historyPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("recent activity")
                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5).textCase(.uppercase)
                Spacer()
                Button("see all") { showHistory = true }
                    .font(.mono(11)).foregroundStyle(c.muted)
            }

            VStack(spacing: 0) {
                ForEach(store.events.prefix(3)) { event in
                    HStack {
                        Image(systemName: event.eventType == "steep_earned" ? "circle.fill" : "gift.fill")
                            .font(.system(size: 8)).foregroundStyle(c.muted)
                        Text(event.eventType == "steep_earned" ? "steep earned" : "reward redeemed")
                            .font(.mono(12)).foregroundStyle(c.text)
                        Spacer()
                        Text(event.createdAt, style: .relative)
                            .font(.mono(10)).foregroundStyle(c.muted)
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, 10)

                    if event.id != store.events.prefix(3).last?.id {
                        Divider().padding(.leading, Spacing.md).opacity(Divide.row)
                    }
                }
            }
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
        }
    }
}

// MARK: - History sheet

struct LoyaltyHistorySheet: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss)       private var dismiss
    let business: Business
    @State private var events: [LoyaltyEvent] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack { ProgressView() }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    Text("no steeps yet")
                        .font(.mono(13)).foregroundStyle(c.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(events) { event in
                        HStack {
                            Image(systemName: event.eventType == "steep_earned" ? "circle.fill" : "gift.fill")
                                .font(.system(size: 8)).foregroundStyle(c.muted)
                            Text(event.eventType == "steep_earned" ? "steep earned" : "reward redeemed")
                                .font(.mono(13)).foregroundStyle(c.text)
                            Spacer()
                            Text(event.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.mono(11)).foregroundStyle(c.muted)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("stamp history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("done") { dismiss() }.font(.mono(13))
            }}
        }
        .fraiseTheme()
        .onAppear {
            guard let token = state.user?.token else { isLoading = false; return }
            Task {
                events = (try? await APIClient.shared.fetchLoyaltyHistory(
                    businessId: business.id, limit: 50, token: token
                )) ?? []
                isLoading = false
            }
        }
    }
}

// MARK: - QR code renderer (CoreImage — no third-party dependency)

private struct QRCodeView: View {
    let content: String

    var body: some View {
        if let image = generateQR() {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1))
        }
    }

    private func generateQR() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Expiry countdown

private struct ExpiryCountdown: View {
    @Environment(\.fraiseColors) private var c
    let expiresAt: Date
    @State private var remaining: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        Text(label)
            .font(.mono(10))
            .foregroundStyle(remaining < 60 ? Color.red : c.muted)
            .onAppear {
                updateRemaining()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    updateRemaining()
                }
            }
            .onDisappear { timer?.invalidate() }
    }

    private var label: String {
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        if remaining <= 0 { return "expired" }
        return String(format: "expires in %d:%02d", mins, secs)
    }

    private func updateRemaining() {
        remaining = max(0, expiresAt.timeIntervalSinceNow)
    }
}

// MARK: - Skeleton placeholder

struct SkeletonBlock: View {
    @Environment(\.fraiseColors) private var c
    let height: CGFloat
    @State private var opacity: Double = 0.4

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.card)
            .fill(c.border)
            .frame(height: height)
            .opacity(opacity)
            .animation(.fraiseSkeleton, value: opacity)
            .onAppear { opacity = 0.8 }
    }
}
