import SwiftUI
import AuthenticationServices

struct AuthPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FraiseBackButton { state.panel = .home }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("box fraise")
                    .font(.system(size: 28, design: .serif))
                    .foregroundStyle(c.text)

                Text("chocolate-covered strawberries, made with a local chocolatier and available at nodes across the city.")
                    .font(.mono(12))
                    .foregroundStyle(c.muted)
                    .lineSpacing(4)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            VStack(alignment: .leading, spacing: 8) {
                Text("order at any node — we deliver fresh when your batch reaches threshold.")
                    .font(.mono(11)).foregroundStyle(c.muted).lineSpacing(3)
                Text("your first pickup verifies your identity and unlocks standing orders.")
                    .font(.mono(11)).foregroundStyle(c.muted).lineSpacing(3)
            }

            if let error {
                Text(error)
                    .font(.mono(11))
                    .foregroundStyle(Color(hex: "C0392B"))
            }

            if loading {
                ProgressView().tint(c.muted)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 25))
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            loading = true
            Task {
                defer { Task { @MainActor in loading = false } }
                do {
                    let response = try await APIClient.shared.appleSignIn(
                        identityToken: token,
                        firstName: cred.fullName?.givenName,
                        lastName:  cred.fullName?.familyName,
                        email:     cred.email
                    )
                    await state.signIn(response: response)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}
