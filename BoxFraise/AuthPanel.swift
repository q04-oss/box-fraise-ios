import SwiftUI
import AuthenticationServices

struct AuthPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var loading = false
    @State private var error: String?

    enum Mode { case signIn, signUp }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FraiseBackButton { state.panel = .home }

                Text("sign in to box fraise")
                    .font(.system(size: 22, design: .serif))
                    .foregroundStyle(c.text)

                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 25))

                // Divider
                HStack {
                    Rectangle().frame(height: 0.5).foregroundStyle(c.border)
                    Text("or").font(.mono(10)).foregroundStyle(c.muted).tracking(1)
                    Rectangle().frame(height: 0.5).foregroundStyle(c.border)
                }

                // Mode toggle
                HStack(spacing: 0) {
                    modeButton("sign in", .signIn)
                    modeButton("create account", .signUp)
                }
                .background(c.searchBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Fields
                VStack(spacing: 10) {
                    if mode == .signUp {
                        fraiseField("name", text: $name)
                    }
                    fraiseField("email", text: $email, keyboard: .emailAddress)
                    fraiseField("password", text: $password, secure: true)
                }

                if let error {
                    Text(error)
                        .font(.mono(11))
                        .foregroundStyle(Color(hex: "C0392B"))
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if loading { ProgressView().tint(.white) }
                        Text(mode == .signIn ? "sign in →" : "create account →")
                            .font(.mono(13, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(c.text)
                    .clipShape(Capsule())
                }
                .disabled(loading)
            }
            .padding(Spacing.md)
        }
    }

    private func modeButton(_ label: String, _ m: Mode) -> some View {
        Button {
            mode = m
            error = nil
        } label: {
            Text(label)
                .font(.mono(11))
                .foregroundStyle(mode == m ? c.text : c.muted)
                .tracking(0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(mode == m ? c.background : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .padding(2)
    }

    private func fraiseField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.mono(9))
                .foregroundStyle(c.muted)
                .tracking(1.5)
                .textCase(.uppercase)
            Group {
                if secure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                        .keyboardType(keyboard)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
            }
            .font(.mono(14))
            .foregroundStyle(c.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(c.searchBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(c.border, lineWidth: 0.5))
        }
    }

    private func submit() async {
        error = nil
        loading = true
        defer { loading = false }
        // Email/password auth not yet wired — Apple Sign In is primary
        error = "use sign in with apple"
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled {
                error = e.localizedDescription
            }
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                error = "apple sign in failed"
                return
            }
            let firstName = cred.fullName?.givenName
            let lastName  = cred.fullName?.familyName
            let email     = cred.email
            loading = true
            Task {
                defer { loading = false }
                do {
                    let response = try await APIClient.shared.appleSignIn(
                        identityToken: token,
                        firstName: firstName,
                        lastName: lastName,
                        email: email
                    )
                    await state.signIn(response: response)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
