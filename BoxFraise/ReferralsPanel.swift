import SwiftUI

struct ReferralsPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var info: ReferralInfo?
    @State private var loading = false
    @State private var applyCode = ""
    @State private var applying = false
    @State private var applyError: String?
    @State private var applySuccess = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                Text("referrals")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                Color.clear.frame(width: 40)
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if loading && info == nil {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in FraiseSkeletonRow(wide: true) }
                    }.padding(Spacing.md)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {

                        // ── Your code ─────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("your code")
                                .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)

                            if let code = info?.code {
                                HStack(spacing: 12) {
                                    Text(code)
                                        .font(.mono(22, weight: .medium)).foregroundStyle(c.text)
                                        .tracking(2)
                                    Spacer()
                                    Button {
                                        UIPasteboard.general.string = code
                                        Haptics.notification(.success)
                                        copied = true
                                        Task {
                                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                                            copied = false
                                        }
                                    } label: {
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 14))
                                            .foregroundStyle(copied ? Color(hex: "4CAF50") : c.muted)
                                    }
                                    if let url = info?.referralUrl.flatMap({ URL(string: $0) }) {
                                        ShareLink(item: url) {
                                            Image(systemName: "square.and.arrow.up")
                                                .font(.system(size: 14)).foregroundStyle(c.muted)
                                        }
                                    }
                                }
                                .padding(Spacing.md)
                                .background(c.card)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))

                                Text("share your code — friends get 10% off their first order.")
                                    .font(.mono(10)).foregroundStyle(c.muted).lineSpacing(3)
                            } else {
                                Text("your code will appear here after your first order.")
                                    .font(.mono(11)).foregroundStyle(c.muted)
                            }
                        }

                        // ── People you've referred ────────────────────────────
                        let referrals = info?.referrals ?? []
                        if !referrals.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(referrals.count) referred")
                                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)

                                VStack(spacing: 0) {
                                    ForEach(referrals) { entry in
                                        HStack {
                                            Text(entry.refereeName?.lowercased() ?? "member")
                                                .font(.mono(13)).foregroundStyle(c.text)
                                            Spacer()
                                            if entry.isCompleted {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(Color(hex: "4CAF50"))
                                                    Text("joined")
                                                        .font(.mono(10)).foregroundStyle(Color(hex: "4CAF50"))
                                                }
                                            } else {
                                                Text("pending")
                                                    .font(.mono(10)).foregroundStyle(c.muted)
                                            }
                                        }
                                        .padding(.horizontal, Spacing.md).padding(.vertical, 13)
                                        .overlay(alignment: .bottom) {
                                            if entry.id != referrals.last?.id {
                                                Rectangle().frame(height: 0.5).foregroundStyle(c.border)
                                            }
                                        }
                                    }
                                }
                                .background(c.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
                            }
                        }

                        // ── Apply a code ──────────────────────────────────────
                        if !applySuccess {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("have a code?")
                                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)

                                HStack(spacing: 10) {
                                    TextField("enter code", text: $applyCode)
                                        .font(.mono(14)).foregroundStyle(c.text)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(c.searchBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))

                                    Button {
                                        guard !applyCode.isEmpty else { return }
                                        Task { await apply() }
                                    } label: {
                                        Text(applying ? "—" : "apply")
                                            .font(.mono(12, weight: .medium)).foregroundStyle(.white)
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(applyCode.isEmpty ? c.border : c.text)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .disabled(applying || applyCode.isEmpty)
                                }

                                if let err = applyError {
                                    Text(err).font(.mono(10)).foregroundStyle(Color(hex: "C0392B"))
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13)).foregroundStyle(Color(hex: "4CAF50"))
                                Text("referral code applied — enjoy 10% off your first order.")
                                    .font(.mono(11)).foregroundStyle(Color(hex: "4CAF50")).lineSpacing(3)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                }
                .refreshable { await load() }
            }
        }
        .task { await load() }
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken else { return }
        loading = true
        info = try? await APIClient.shared.fetchReferralInfo(token: token)
        loading = false
    }

    @MainActor private func apply() async {
        guard let token = Keychain.userToken else { return }
        applying = true; applyError = nil
        do {
            try await APIClient.shared.applyReferralCode(applyCode.trimmingCharacters(in: .whitespaces), token: token)
            Haptics.notification(.success)
            applySuccess = true
        } catch {
            applyError = error.localizedDescription
            Haptics.notification(.error)
        }
        applying = false
    }
}
