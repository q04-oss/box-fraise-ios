import SwiftUI

// MARK: - Safety number sheet
//
// Displays a 30-digit fingerprint derived from both parties' identity keys.
// Both users compute the same number independently on their own devices —
// a match confirms the server has not substituted either party's key.
// Mismatch: treat as a potential MitM until verified by voice or in person.

struct SafetyNumberSheet: View {
    @Environment(\.fraiseColors) private var c
    @Environment(\.dismiss) private var dismiss

    let contactName: String
    let contactId: Int
    let myUserId: Int

    @State private var number: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "safety number") { dismiss() }

            ScrollView {
                VStack(spacing: 28) {
                    if let n = number {
                        // Icon + explanation
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(c.text)
                            Text("compare this number with \(contactName.lowercased()) — read it aloud or scan QR codes. a match confirms your conversation is private.")
                                .font(.mono(12))
                                .foregroundStyle(c.muted)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, Spacing.lg)

                        // Fingerprint grid — 6 groups of 5 digits, displayed 3×2
                        let groups = n.components(separatedBy: " ")
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(groups, id: \.self) { group in
                                Text(group)
                                    .font(.system(.title3, design: .monospaced).weight(.medium))
                                    .foregroundStyle(c.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(c.card)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                            .strokeBorder(c.border, lineWidth: 0.5)
                                    )
                            }
                        }
                        .padding(.horizontal, Spacing.lg)

                        // Copy button
                        Button {
                            UIPasteboard.general.string = groups.joined()
                            Haptics.impact(.light)
                        } label: {
                            Label("copy", systemImage: "doc.on.doc")
                                .font(.mono(12))
                                .foregroundStyle(c.muted)
                        }

                        Divider()
                            .padding(.horizontal, Spacing.lg)

                        // What a mismatch means
                        VStack(alignment: .leading, spacing: 8) {
                            Text("if the numbers differ")
                                .font(.system(size: 13, design: .serif))
                                .foregroundStyle(c.text)
                            Text("do not exchange sensitive information. contact \(contactName.lowercased()) through a separate channel to verify their account, then check again.")
                                .font(.mono(11))
                                .foregroundStyle(c.muted)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.lg)

                    } else {
                        // TOFU not yet established — no key recorded for this contact
                        VStack(spacing: 12) {
                            Image(systemName: "lock.slash")
                                .font(.system(size: 30))
                                .foregroundStyle(c.muted)
                            Text("not yet available")
                                .font(.system(size: 15, design: .serif))
                                .foregroundStyle(c.text)
                            Text("exchange at least one message with \(contactName.lowercased()) first. the safety number is generated once their encryption key has been recorded on this device.")
                                .font(.mono(12))
                                .foregroundStyle(c.muted)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, Spacing.lg)
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
        }
        .presentationDragIndicator(.visible)
        .task { computeNumber() }
    }

    private func computeNumber() {
        let myKey = MessagingKeyStore.identityKey.publicKeyBytes
        guard let theirKey = MessagingKeyStore.knownIdentityKey(for: contactId) else { return }
        number = safetyNumber(
            myUserId: myUserId, myIdentityKey: myKey,
            theirUserId: contactId, theirIdentityKey: theirKey
        )
    }
}

#Preview("number available") {
    SafetyNumberSheet(contactName: "alice", contactId: 1, myUserId: 2)
        .fraiseTheme()
}

#Preview("not yet available") {
    SafetyNumberSheet(contactName: "bob", contactId: 999, myUserId: 2)
        .fraiseTheme()
}
