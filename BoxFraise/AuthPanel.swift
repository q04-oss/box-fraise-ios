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

            Text("sign in to box fraise")
                .font(.system(size: 22, design: .serif))
                .foregroundStyle(c.text)

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
