import SwiftUI
import AuthenticationServices

struct AccountTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.colorScheme) var scheme

    @State private var authMode: AuthMode = .signIn
    @State private var name = "", email = "", password = ""
    @State private var loading = false
    @State private var error: String? = nil
    @State private var showCredits = false

    enum AuthMode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    appState.isSignedIn ? AnyView(signedInView) : AnyView(authView)
                }
                .padding(Spacing.lg)
            }
            .background(c.background)
            .navigationTitle(appState.member?.name ?? "account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
        }
        .sheet(isPresented: $showCredits) { CreditsView() }
    }

    // MARK: - Signed in

    private var signedInView: some View {
        let m = appState.member
        let credits = m?.creditBalance ?? 0
        return VStack(spacing: Spacing.md) {
            CardRows(rows: [
                "standing":       "\(m?.standing ?? 0)",
                "email":          m?.email ?? "",
                "credit balance": "\(credits) credit\(credits == 1 ? "" : "s")",
                "events attended":"\(m?.eventsAttended ?? 0)",
            ])
            if let rate = m?.responseRate {
                CardRows(rows: ["response rate": "\(rate)%"])
            }
            PrimaryButton(label: "buy credits →") { showCredits = true }
            GhostButton(label: "sign out") { appState.signOut() }
        }
    }

    // MARK: - Auth

    private var authView: some View {
        VStack(spacing: Spacing.md) {
            SignInWithAppleButton(onRequest: { $0.requestedScopes = [.fullName, .email] }, onCompletion: handleAppleResult)
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 44).clipShape(Capsule())

            OrDivider()

            HStack(spacing: Spacing.lg) {
                modeButton("sign in", .signIn)
                modeButton("create account", .signUp)
            }

            VStack(spacing: Spacing.sm) {
                if authMode == .signUp {
                    MonoField(label: "your name", placeholder: "full name", text: $name, autocapitalization: .words)
                }
                MonoField(label: "email", placeholder: "you@example.com", text: $email,
                          keyboardType: .emailAddress, textContentType: .emailAddress)
                MonoField(label: "password", placeholder: authMode == .signUp ? "8+ characters" : "••••••••",
                          text: $password, secure: true,
                          textContentType: authMode == .signUp ? .newPassword : .password,
                          submitLabel: .go, onSubmit: submit)
            }

            if let error { ErrorText(message: error) }

            PrimaryButton(label: authMode == .signIn ? "sign in →" : "create account →", loading: loading, action: submit)
        }
    }

    private func modeButton(_ label: String, _ mode: AuthMode) -> some View {
        Button(label) { authMode = mode; error = nil }
            .font(.mono(13)).foregroundStyle(authMode == mode ? c.text : c.muted)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                if authMode == mode { Rectangle().frame(height: 1.5).foregroundStyle(c.text) }
            }
    }

    // MARK: - Actions

    private func submit() {
        error = nil
        Task {
            loading = true
            do {
                let member: FraiseMember
                let e = email.trimmingCharacters(in: .whitespaces).lowercased()
                if authMode == .signIn {
                    guard !e.isEmpty, !password.isEmpty else { error = "email and password required."; loading = false; return }
                    member = try await APIClient.shared.login(email: e, password: password)
                } else {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty, !e.isEmpty, password.count >= 8 else { error = "name, email, and password (8+ chars) required."; loading = false; return }
                    member = try await APIClient.shared.signup(name: n, email: e, password: password)
                }
                await finalize(member)
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code != .canceled { error = err.localizedDescription }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let tokenStr  = String(data: tokenData, encoding: .utf8) else { error = "apple sign in failed."; return }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
            Task {
                loading = true
                do { await finalize(try await APIClient.shared.appleSignIn(identityToken: tokenStr, name: fullName.isEmpty ? nil : fullName, email: cred.email)) }
                catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }

    private func finalize(_ member: FraiseMember) async {
        await appState.signIn(member: member)
        name = ""; email = ""; password = ""
    }
}
