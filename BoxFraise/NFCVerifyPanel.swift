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
            Button { state.panel = .home } label: {
                Text("← back")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }

            Text("verify pickup")
                .font(.system(size: 28, design: .serif))
                .foregroundStyle(c.text)

            if let result {
                // Verified result
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Circle()
                            .fill(Color(hex: "4CAF50"))
                            .frame(width: 10, height: 10)
                        Text("verified")
                            .font(.mono(11))
                            .foregroundStyle(Color(hex: "4CAF50"))
                            .tracking(1)
                            .textCase(.uppercase)
                    }

                    if let name = result.varietyName {
                        Text(name.lowercased())
                            .font(.system(size: 22, design: .serif))
                            .foregroundStyle(c.text)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        if let q = result.quantity {
                            resultRow("quantity", value: "\(q) boxes")
                        }
                        if let farm = result.farm {
                            resultRow("farm", value: farm.lowercased())
                        }
                        if let date = result.harvestDate {
                            resultRow("harvested", value: date)
                        }
                    }
                    .padding(Spacing.md)
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

                    Button {
                        self.result = nil
                        error = nil
                    } label: {
                        Text("scan another")
                            .font(.mono(12))
                            .foregroundStyle(c.muted)
                    }
                    .padding(.top, Spacing.sm)
                }
            } else {
                // Scan prompt
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("hold your phone near the NFC chip inside your box lid.")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)

                    if let error {
                        Text(error)
                            .font(.mono(11))
                            .foregroundStyle(Color(hex: "C0392B"))
                    }

                    Button {
                        startScan()
                    } label: {
                        HStack {
                            if scanning { ProgressView().tint(.white) }
                            Text(scanning ? "scanning…" : "scan box  →")
                                .font(.mono(13, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(c.text)
                        .clipShape(Capsule())
                    }
                    .disabled(scanning)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    private func resultRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.mono(10))
                .foregroundStyle(c.muted)
                .tracking(1)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.mono(13))
                .foregroundStyle(c.text)
        }
    }

    private func startScan() {
        guard NFCTagReaderSession.readingAvailable else {
            error = "NFC is not available on this device."
            return
        }
        scanning = true
        error = nil

        let d = NFCScanDelegate { token in
            Task { @MainActor in
                await verify(token: token)
            }
        } onError: { msg in
            Task { @MainActor in
                scanning = false
                error = msg
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
        } catch {
            scanning = false
            self.error = error.localizedDescription
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
        if let e = error as? NFCReaderError, e.code == .readerSessionInvalidationErrorUserCanceled { return }
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
                // Read identifier as hex token
                let token = mifareTag.identifier.map { String(format: "%02x", $0) }.joined()
                session.alertMessage = "Box verified."
                session.invalidate()
                self.onRead(token)
            } else {
                session.invalidate(errorMessage: "Unsupported tag type.")
                self.onError("Unsupported NFC tag.")
            }
        }
    }
}
