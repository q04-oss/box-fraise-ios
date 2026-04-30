import SwiftUI

/// Shown when the user taps the password-reset Universal Link from their email.
/// The token is extracted from the URL by BoxFraiseApp.handleDeepLink and passed
/// in here — the view never touches the URL directly.
struct ResetPasswordPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.fraiseColors) private var c

    let token: String

    @State private var newPassword     = ""
    @State private var confirmPassword = ""
    @State private var phase: Phase    = .idle

    private enum Phase {
        case idle, loading, success
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("reset password")
                    .font(.mono(22))
                    .foregroundStyle(c.primary)

                Text("choose a new password for your account.")
                    .font(.mono(13))
                    .foregroundStyle(c.secondary)

                VStack(spacing: Spacing.sm) {
                    SecureField("new password", text: $newPassword)
                        .textContentType(.newPassword)
                        .fraiseTextField()

                    SecureField("confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .fraiseTextField()
                }

                switch phase {
                case .idle, .loading:
                    Button(action: submit) {
                        Group {
                            if case .loading = phase {
                                ProgressView().tint(c.background)
                            } else {
                                Text("set new password")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FraiseButtonStyle())
                    .disabled(isDisabled)

                case .success:
                    VStack(spacing: Spacing.sm) {
                        Text("password updated")
                            .font(.mono(14))
                            .foregroundStyle(c.primary)
                        Button("sign in") { appState.navigate(to: .auth) }
                            .buttonStyle(FraiseButtonStyle())
                    }

                case .error(let msg):
                    Text(msg)
                        .font(.mono(12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, Spacing.xs)

                    Button(action: submit) {
                        Text("try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FraiseButtonStyle())
                    .disabled(isDisabled)
                }
            }
            .padding(Spacing.lg)
        }
        .fraiseTheme()
    }

    private var isDisabled: Bool {
        newPassword.count < 8 || confirmPassword != newPassword
    }

    private func submit() {
        guard newPassword == confirmPassword, newPassword.count >= 8 else {
            phase = .error(newPassword.count < 8
                ? "password must be at least 8 characters"
                : "passwords don't match")
            return
        }
        phase = .loading
        Task {
            do {
                try await APIClient.shared.resetPassword(token: token, newPassword: newPassword)
                phase = .success
            } catch {
                phase = .error("reset failed — the link may have expired. request a new one.")
            }
        }
    }
}

#Preview {
    ResetPasswordPanel(token: "preview-token")
        .fraiseTheme()
}
