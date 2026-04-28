import SwiftUI
import CoreNFC

struct NFCVerifyPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var scanning = false
    @State private var outcome: ScanOutcome?
    @State private var error: String?
    @State private var delegate: NFCScanDelegate?
    @State private var addedBusinessCode: String?

    enum ScanOutcome {
        case firstVerify(NFCVerifyResult)
        case reorder(NFCReorderResult)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FraiseBackButton { state.panel = .profile }

            switch outcome {
            case .firstVerify(let r): verifiedView(r)
            case .reorder(let r):     provenanceView(r)
            case nil:                 scanView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    // MARK: - First verify

    private func verifiedView(_ r: NFCVerifyResult) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {

                // Hero badge
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color(hex: "4CAF50").opacity(0.12)).frame(width: 48, height: 48)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(hex: "4CAF50"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("verified")
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(Color(hex: "4CAF50"))
                            .tracking(1.5).textCase(.uppercase)
                        Text("authentic box fraise")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(0.3)
                    }
                }

                if let name = r.varietyName {
                    Text(name.lowercased())
                        .font(.system(size: 32, design: .serif)).foregroundStyle(c.text)
                }

                // Time bank card
                if let credits = r.creditsAddedDays {
                    let milestone = r.streakMilestone ?? false
                    VStack(spacing: 0) {
                        bankRow("+\(credits) days", label: "earned", icon: "clock.badge.plus",
                                accent: Color(hex: "4CAF50"))
                        if let bank = r.bankDays {
                            bankRow("\(bank) days", label: "in bank", icon: "clock")
                        }
                        if let lifetime = r.lifetimeDays {
                            bankRow("\(lifetime) days", label: "lifetime", icon: "infinity")
                        }
                        if let streak = r.streakWeeks {
                            bankRow("week \(streak)\(milestone ? " ★" : "")",
                                    label: milestone ? "milestone" : "streak",
                                    icon: milestone ? "star.fill" : "flame",
                                    accent: milestone ? Color(hex: "F9A825") : nil)
                        }
                    }
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                        milestone ? Color(hex: "F9A825").opacity(0.5) : c.border,
                        lineWidth: milestone ? 1 : 0.5))
                }

                // fraise.chat identity — first time
                if let email = r.fraiseChatEmail {
                    Button { state.panel = .messages } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("your fraise identity")
                                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                                Text(email)
                                    .font(.mono(14)).foregroundStyle(c.text)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11)).foregroundStyle(Color(hex: "4CAF50").opacity(0.6))
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(c.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                            Color(hex: "4CAF50").opacity(0.4), lineWidth: 0.5))
                    }
                }

                // Unlocked features
                if let unlocked = r.unlocked, !unlocked.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("unlocked")
                            .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                        ForEach(unlocked, id: \.self) { feature in
                            HStack(spacing: 10) {
                                Image(systemName: "lock.open.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "4CAF50"))
                                Text(feature.replacingOccurrences(of: "_", with: " ").lowercased())
                                    .font(.mono(12)).foregroundStyle(c.text)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                }

                // Provenance
                if r.quantity != nil || r.farm != nil || r.harvestDate != nil {
                    VStack(spacing: 0) {
                        if let q = r.quantity    { detailRow("quantity",  value: "\(q) boxes", icon: "cube.box") }
                        if let f = r.farm        { detailRow("farm",      value: f.lowercased(), icon: "leaf") }
                        if let d = r.harvestDate { detailRow("harvested", value: d, icon: "calendar") }
                    }
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                }

                // Business contact
                if let code = r.businessUserCode, let name = r.businessName {
                    businessContactButton(code: code, name: name)
                }

                doneButton
            }
        }
    }

    // MARK: - Provenance (re-scan)

    private func provenanceView(_ r: NFCReorderResult) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(c.muted)
                    Text("already collected")
                        .font(.mono(11)).foregroundStyle(c.muted).tracking(0.5)
                }

                if let name = r.varietyName {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.lowercased())
                            .font(.system(size: 32, design: .serif)).foregroundStyle(c.text)
                        if let count = r.orderCount {
                            let suffix = ["st","nd","rd"][min(count-1, 2) < 3 && (count < 11 || count > 13)
                                                          ? max(0, min(count-1, 2)) : 2]
                            Text("your \(count)\(suffix) box")
                                .font(.mono(11)).foregroundStyle(c.muted)
                        }
                    }
                }

                // Provenance card
                VStack(spacing: 0) {
                    if let f = r.farm            { detailRow("farm",      value: f.lowercased(), icon: "leaf") }
                    if let d = r.harvestDate     { detailRow("harvested", value: d, icon: "calendar") }
                    if let b = r.batchDeliveryDate { detailRow("delivered", value: b, icon: "shippingbox") }
                    if let n = r.batchNotes, !n.isEmpty {
                        detailRow("notes", value: n.lowercased(), icon: "text.quote")
                    }
                }
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))

                // Collectif pickups
                if let count = r.collectifPickupsToday, count > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(count) collectif member\(count == 1 ? "" : "s") also picked up today")
                            .font(.mono(11)).foregroundStyle(c.muted)
                        if let names = r.collectifMemberNames, !names.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(names, id: \.self) { n in
                                    Text(n)
                                        .font(.mono(10)).foregroundStyle(c.text)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(c.searchBg).clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                }

                // Last variety
                if let last = r.lastVariety, let name = last.name {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("last time").font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                        Text(name.lowercased()).font(.mono(13)).foregroundStyle(c.text)
                        if let f = last.farm {
                            Text(f.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                        }
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                }

                // Next standing order
                if let next = r.nextStandingOrder, let variety = next.varietyName {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("next order").font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                        HStack {
                            Text(variety.lowercased()).font(.mono(13)).foregroundStyle(c.text)
                            Spacer()
                            if let days = next.daysUntil {
                                Text("in \(days)d").font(.mono(11)).foregroundStyle(c.muted)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
                }

                doneButton
            }
        }
    }

    // MARK: - Scan prompt

    private var scanView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("verify pickup")
                .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("hold your phone near the NFC chip inside your box lid.")
                    .font(.mono(13)).foregroundStyle(c.muted).lineSpacing(4)
                Text("the chip is embedded in the lid — no sticker needed.")
                    .font(.mono(11)).foregroundStyle(c.border).lineSpacing(3)
            }

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(Color(hex: "C0392B"))
                    Text(error).font(.mono(11)).foregroundStyle(Color(hex: "C0392B"))
                }
            }

            Button { startScan() } label: {
                HStack {
                    if scanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    }
                    Text(scanning ? "scanning…" : "scan box")
                        .font(.mono(13, weight: .medium)).foregroundStyle(.white)
                    if !scanning {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                .background(c.text)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(scanning)
        }
    }

    // MARK: - Row helpers

    private func bankRow(_ value: String, label: String, icon: String, accent: Color? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(accent ?? c.muted)
                .frame(width: 20)
            Text(label)
                .font(.mono(10)).foregroundStyle(c.muted).tracking(1).textCase(.uppercase)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.mono(13))
                .foregroundStyle(accent ?? c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13)).foregroundStyle(c.muted).frame(width: 20)
            Text(label)
                .font(.mono(10)).foregroundStyle(c.muted).tracking(1).textCase(.uppercase)
                .frame(width: 70, alignment: .leading)
            Text(value).font(.mono(13)).foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }

    private func businessContactButton(code: String, name: String) -> some View {
        let added = addedBusinessCode == code
        return Button {
            guard !added, let token = Keychain.userToken else { return }
            addedBusinessCode = code
            Haptics.impact(.light)
            Task { try? await APIClient.shared.addBusinessContact(businessCode: code, token: token) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: added ? "checkmark.circle.fill" : "mappin.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(added ? Color(hex: "4CAF50") : c.muted)
                Text(added ? "added to messages" : "message \(name.lowercased())")
                    .font(.mono(12)).foregroundStyle(c.text)
                Spacer()
                if !added {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11)).foregroundStyle(c.muted)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                added ? Color(hex: "4CAF50").opacity(0.4) : c.border,
                lineWidth: 0.5))
        }
        .disabled(added)
    }

    private var doneButton: some View {
        Button { outcome = nil; error = nil } label: {
            HStack {
                Text("done").font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.md).padding(.vertical, 16)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        }
    }

    // MARK: - NFC

    private func startScan() {
        guard NFCTagReaderSession.readingAvailable else {
            error = "NFC is not available on this device."
            return
        }
        Haptics.impact(.medium)
        scanning = true; error = nil
        let d = NFCScanDelegate { token in
            Task { @MainActor in await verify(token: token) }
        } onError: { msg in
            Task { @MainActor in
                scanning = false
                error = msg.isEmpty ? nil : msg
            }
        }
        delegate = d
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: d)
        session?.alertMessage = "Hold near the NFC chip inside your box lid."
        session?.begin()
    }

    @MainActor private func verify(token nfcToken: String) async {
        guard let userToken = Keychain.userToken else {
            scanning = false
            error = "sign in to verify your pickup"
            return
        }
        do {
            let r = try await APIClient.shared.verifyNFC(token: nfcToken, userToken: userToken)
            scanning = false
            outcome = .firstVerify(r)
            if let user = state.user {
                state.user = BoxUser(id: user.id, displayName: user.displayName, verified: true)
            }
            Haptics.notification(.success)
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("already") || msg.contains("used") || msg.contains("invalid") {
                await tryReorder(token: nfcToken, userToken: userToken)
            } else {
                scanning = false
                self.error = error.localizedDescription
                Haptics.notification(.error)
            }
        }
    }

    @MainActor private func tryReorder(token nfcToken: String, userToken: String) async {
        do {
            let r = try await APIClient.shared.verifyNFCReorder(token: nfcToken, userToken: userToken)
            scanning = false
            outcome = .reorder(r)
            Haptics.notification(.success)
        } catch {
            scanning = false
            self.error = "this token could not be verified"
            Haptics.notification(.error)
        }
    }
}

// MARK: - NFC Delegate

final class NFCScanDelegate: NSObject, NFCTagReaderSessionDelegate {
    private let onRead: (String) -> Void
    private let onError: (String) -> Void

    init(onRead: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onRead = onRead
        self.onError = onError
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let e = error as? NFCReaderError, e.code == .readerSessionInvalidationErrorUserCanceled {
            Task { @MainActor in onError("") }
            return
        }
        onError(error.localizedDescription)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                self.onError(error.localizedDescription)
                return
            }
            if case .miFare(let mifareTag) = tag {
                let token = mifareTag.identifier.map { String(format: "%02x", $0) }.joined()
                self.onRead(token)
                session.invalidate()
            } else {
                session.invalidate(errorMessage: "Unsupported tag type.")
                self.onError("Unsupported NFC tag.")
            }
        }
    }
}
