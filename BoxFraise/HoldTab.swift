import SwiftUI
import AuthenticationServices

struct HoldTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.colorScheme) var scheme

    @State private var authMode: AuthMode = .signIn
    @State private var name      = ""
    @State private var email     = ""
    @State private var password  = ""
    @State private var resetCode = ""
    @State private var codeSent  = false
    @State private var loading   = false
    @State private var error: String? = nil
    @State private var showCredits = false

    enum AuthMode { case signIn, signUp, forgot, reset }

    var body: some View {
        Group {
            if appState.isSignedIn { creditView }
            else                   { authView }
        }
        .sheet(isPresented: $showCredits) { CreditsView() }
    }

    // MARK: - Credit centerpiece

    private var creditView: some View {
        let m       = appState.member
        let credits = m?.creditBalance ?? 0
        let standing = m?.standing ?? 0

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Name — top left
                HStack {
                    Text(m?.name ?? "")
                        .font(.mono(12)).foregroundStyle(c.muted)
                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

                Spacer()

                MetricDisplay(
                    value: "\(credits)",
                    label: (credits == 1 ? "akène" : "akènes") + " held"
                )

                Spacer().frame(height: Spacing.xl)

                MetricDisplay(
                    value: "\(standing)",
                    label: "standing",
                    size: 34,
                    valueColor: c.muted,
                    labelColor: c.border
                )

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom actions
            VStack(spacing: Spacing.sm) {
                if credits == 0 {
                    Text("hold an akène to be considered.")
                        .font(.mono(12)).foregroundStyle(c.muted).multilineTextAlignment(.center)
                }
                PrimaryButton(label: credits == 0 ? "buy an akène — CA$120 →" : "buy more →") {
                    showCredits = true
                }
                Button("sign out") { appState.signOut() }
                    .font(.mono(10)).foregroundStyle(c.border).tracking(1)
                    .padding(.bottom, 4)
            }
            .padding(Spacing.lg)
        }
        .background(c.background)
        .refreshable { await appState.bootstrap() }
    }

    // MARK: - Auth screen

    private var authView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Wordmark
                VStack(spacing: Spacing.xs) {
                    Text("box fraise")
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundStyle(c.text)
                    Text("a private network.\nhold an akène. get considered.")
                        .font(.mono(12)).foregroundStyle(c.muted)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.xl)

                if authMode == .forgot {
                    forgotView
                } else if authMode == .reset {
                    resetView
                } else {
                    signInSignUpView
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(c.background)
    }

    private var signInSignUpView: some View {
        VStack(spacing: Spacing.lg) {
            // Apple Sign In
            SignInWithAppleButton(
                onRequest: { $0.requestedScopes = [.fullName, .email] },
                onCompletion: handleAppleResult
            )
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 44).clipShape(Capsule())

            OrDivider()

            // Mode toggle
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
                MonoField(label: "password",
                          placeholder: authMode == .signUp ? "8+ characters" : "••••••••",
                          text: $password, secure: true,
                          textContentType: authMode == .signUp ? .newPassword : .password,
                          submitLabel: .go, onSubmit: submit)
            }

            if let error { ErrorText(message: error) }

            PrimaryButton(
                label: authMode == .signIn ? "sign in →" : "create account →",
                loading: loading,
                action: submit
            )

            if authMode == .signIn {
                Button("forgot password?") {
                    error = nil
                    authMode = .forgot
                }
                .font(.mono(12)).foregroundStyle(c.muted)
            }
        }
    }

    private var forgotView: some View {
        VStack(spacing: Spacing.lg) {
            Text("enter your email and we'll send a reset code.")
                .font(.mono(12)).foregroundStyle(c.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            MonoField(label: "email", placeholder: "you@example.com", text: $email,
                      keyboardType: .emailAddress, textContentType: .emailAddress,
                      submitLabel: .send, onSubmit: submitForgot)

            if let error { ErrorText(message: error) }

            PrimaryButton(label: "send code →", loading: loading, action: submitForgot)

            Button("back to sign in") { authMode = .signIn; error = nil }
                .font(.mono(12)).foregroundStyle(c.muted)
        }
    }

    private var resetView: some View {
        VStack(spacing: Spacing.lg) {
            if codeSent {
                Text("code sent — check your email.")
                    .font(.mono(12)).foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: Spacing.sm) {
                MonoField(label: "email", placeholder: "you@example.com", text: $email,
                          keyboardType: .emailAddress, textContentType: .emailAddress)
                MonoField(label: "reset code", placeholder: "6-character code", text: $resetCode)
                MonoField(label: "new password", placeholder: "8+ characters",
                          text: $password, secure: true, textContentType: .newPassword,
                          submitLabel: .go, onSubmit: submitReset)
            }

            if let error { ErrorText(message: error) }

            PrimaryButton(label: "reset password →", loading: loading, action: submitReset)

            Button("back to sign in") { authMode = .signIn; error = nil }
                .font(.mono(12)).foregroundStyle(c.muted)
        }
    }

    // MARK: - Helpers

    private func submitForgot() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !e.isEmpty else { error = "enter your email first."; return }
        error = nil
        Task {
            loading = true
            do {
                try await APIClient.shared.forgotPassword(email: e)
                codeSent = true
                authMode = .reset
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }

    private func submitReset() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        let code = resetCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !e.isEmpty, !code.isEmpty, password.count >= 8 else {
            error = "email, code, and new password (8+ chars) required."
            return
        }
        error = nil
        Task {
            loading = true
            do {
                try await APIClient.shared.resetPassword(email: e, code: code, password: password)
                name = ""; email = ""; password = ""; resetCode = ""; codeSent = false
                authMode = .signIn
            } catch { self.error = error.localizedDescription }
            loading = false
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

    private func submit() {
        error = nil
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        let n = name.trimmingCharacters(in: .whitespaces)
        if authMode == .signIn {
            guard !e.isEmpty, !password.isEmpty else { error = "email and password required."; return }
        } else {
            guard !n.isEmpty, !e.isEmpty, password.count >= 8 else { error = "name, email, and password (8+ chars) required."; return }
        }
        Task {
            loading = true
            do {
                let member: FraiseMember
                if authMode == .signIn {
                    member = try await APIClient.shared.login(email: e, password: password)
                } else {
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
            guard let cred     = auth.credential as? ASAuthorizationAppleIDCredential,
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
