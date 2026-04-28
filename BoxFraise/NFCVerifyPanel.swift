import SwiftUI
import CoreNFC

struct NFCVerifyPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var scanning = false
    @State private var result: NFCVerifyResult?
    @State private var error: String?
    @State private var delegate: NFCScanDelegate?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FraiseBackButton { state.panel = .profile }

            if let result {
                verifiedView(result)
            } else {
                scanView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    // MARK: - Verified

    private func verifiedView(_ result: NFCVerifyResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Badge
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: "4CAF50").opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "4CAF50"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("verified")
                        .font(.mono(11, weight: .medium))
                        .foregroundStyle(Color(hex: "4CAF50"))
                        .tracking(1.5)
                        .textCase(.uppercase)
                    Text("authentic box fraise product")
                        .font(.mono(9))
                        .foregroundStyle(c.muted)
                        .tracking(0.3)
                }
            }

            // Variety name
            if let name = result.varietyName {
                Text(name.lowercased())
                    .font(.system(size: 32, design: .serif))
                    .foregroundStyle(c.text)
            }

            // Details card
            if result.quantity != nil || result.farm != nil || result.harvestDate != nil {
                VStack(spacing: 0) {
                    if let q = result.quantity {
                        detailRow("quantity", value: "\(q) boxes", icon: "cube.box")
                    }
                    if let farm = result.farm {
                        detailRow("farm", value: farm.lowercased(), icon: "leaf")
                    }
                    if let date = result.harvestDate {
                        detailRow("harvested", value: date, icon: "calendar")
                    }
                }
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
            }

            // Scan another
            Button {
                self.result = nil
                error = nil
            } label: {
                HStack {
                    Text("scan another")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11))
                        .foregroundStyle(c.border)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Scan prompt

    private var scanView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("verify pickup")
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(c.text)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("hold your phone near the NFC chip inside your box lid.")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
                    .lineSpacing(4)

                Text("the chip is embedded in the lid — no sticker needed.")
                    .font(.mono(11))
                    .foregroundStyle(c.border)
                    .lineSpacing(3)
            }

            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "C0392B"))
                    Text(error)
                        .font(.mono(11))
                        .foregroundStyle(Color(hex: "C0392B"))
                }
            }

            Button { startScan() } label: {
                HStack {
                    if scanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Text(scanning ? "scanning…" : "scan box")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(.white)
                    if !scanning {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 16)
                .background(c.text)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(scanning)
        }
    }

    // MARK: - Row helper

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(c.muted)
                .frame(width: 20)
            Text(label)
                .font(.mono(10))
                .foregroundStyle(c.muted)
                .tracking(1)
                .textCase(.uppercase)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.mono(13))
                .foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }

    // MARK: - NFC

    private func startScan() {
        guard NFCTagReaderSession.readingAvailable else {
            error = "NFC is not available on this device."
            return
        }
        Haptics.impact(.medium)
        scanning = true
        error = nil

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
            result = r
            Haptics.notification(.success)
        } catch {
            scanning = false
            self.error = error.localizedDescription
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
