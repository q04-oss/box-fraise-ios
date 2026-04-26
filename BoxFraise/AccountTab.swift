import SwiftUI
import AuthenticationServices

struct AccountTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.colorScheme) var scheme

    @State private var authMode: AuthMode = .signIn
    @State private var name     = ""
    @State private var email    = ""
    @State private var password = ""
    @State private var loading  = false
    @State private var error: String? = nil
    @State private var showCredits = false

    enum AuthMode { case signIn, signUp }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    if appState.isSignedIn {
                        signedInView
                    } else {
                        authView
                    }
                }
                .padding(Spacing.lg)
            }
            .background(c.background)
            .navigationTitle(appState.member?.name ?? "account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
        }
        .sheet(isPresented: $showCredits) {
            CreditsView()
        }
    }

    // MARK: - Signed in

    private var signedInView: some View {
        VStack(spacing: Spacing.md) {
            FraiseCard {
                StatRow(label: "standing",       value: "\(appState.member?.standing ?? 0)", topBorder: false)
                StatRow(label: "email",          value: appState.member?.email ?? "")
                StatRow(label: "credit balance", value: creditLabel)
                StatRow(label: "events attended",value: "\(appState.member?.eventsAttended ?? 0)")
                if let rate = appState.member?.responseRate {
                    StatRow(label: "response rate", value: "\(rate)%")
                }
            }

            PrimaryButton(label: "buy credits →") {
                showCredits = true
            }

            GhostButton(label: "sign out") {
                appState.signOut()
            }
        }
    }

    private var creditLabel: String {
        let n = appState.member?.creditBalance ?? 0
        return "\(n) credit\(n == 1 ? "" : "s")"
    }

    // MARK: - Auth

    private var authView: some View {
        VStack(spacing: Spacing.md) {
            // Apple Sign In — primary action
            SignInWithAppleButton(
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: handleAppleResult
            )
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 44)
            .clipShape(Capsule())

            OrDivider()

            // Mode toggle
            HStack(spacing: Spacing.lg) {
                modeButton("sign in",       mode: .signIn)
                modeButton("create account", mode: .signUp)
            }

            // Form fields
            VStack(spacing: Spacing.sm) {
                if authMode == .signUp {
                    MonoField(
                        label: "your name",
                        placeholder: "full name",
                        text: $name,
                        autocapitalization: .words
                    )
                }
                MonoField(
                    label: "email",
                    placeholder: "you@example.com",
                    text: $email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
                MonoField(
                    label: "password",
                    placeholder: authMode == .signUp ? "8+ characters" : "••••••••",
                    text: $password,
                    secure: true,
                    textContentType: authMode == .signUp ? .newPassword : .password,
                    submitLabel: .go,
                    onSubmit: submit
                )
            }

            if let error { ErrorText(message: error) }

            PrimaryButton(
                label: authMode == .signIn ? "sign in →" : "create account →",
                loading: loading,
                action: submit
            )
        }
    }

    private func modeButton(_ label: String, mode: AuthMode) -> some View {
        Button(label) {
            authMode = mode
            error = nil
        }
        .font(.mono(13))
        .foregroundStyle(authMode == mode ? c.text : c.muted)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            if authMode == mode {
                Rectangle()
                    .frame(height: 1.5)
                    .foregroundStyle(c.text)
            }
        }
    }

    // MARK: - Actions

    private func submit() {
        error = nil
        Task {
            loading = true
            do {
                let member: FraiseMember
                if authMode == .signIn {
                    guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
                        error = "email and password required."
                        loading = false
                        return
                    }
                    member = try await APIClient.shared.login(
                        email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                        password: password
                    )
                } else {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
                          !email.trimmingCharacters(in: .whitespaces).isEmpty,
                          password.count >= 8 else {
                        error = "name, email, and password (8+ chars) required."
                        loading = false
                        return
                    }
                    member = try await APIClient.shared.signup(
                        name: name.trimmingCharacters(in: .whitespaces),
                        email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                        password: password
                    )
                }
                await appState.signIn(member: member)
                name = ""; email = ""; password = ""
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let err):
            let code = (err as? ASAuthorizationError)?.code
            if code != .canceled { error = err.localizedDescription }

        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData  = credential.identityToken,
                  let tokenStr   = String(data: tokenData, encoding: .utf8) else {
                error = "apple sign in failed."
                return
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task {
                loading = true
                do {
                    let member = try await APIClient.shared.appleSignIn(
                        identityToken: tokenStr,
                        name: fullName.isEmpty ? nil : fullName,
                        email: credential.email
                    )
                    await appState.signIn(member: member)
                } catch {
                    self.error = error.localizedDescription
                }
                loading = false
            }
        }
    }
}
