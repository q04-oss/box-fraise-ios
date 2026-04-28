import SwiftUI

struct ProfilePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Button { state.panel = .home } label: {
                    Text("← back")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                }

                if let user = state.user {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.displayName?.lowercased() ?? "member")
                            .font(.system(size: 28, design: .serif))
                            .foregroundStyle(c.text)
                        if user.verified == true {
                            Text("verified")
                                .font(.mono(10))
                                .foregroundStyle(c.muted)
                                .tracking(1.5)
                        }
                    }

                    Divider().foregroundStyle(c.border)

                    VStack(spacing: 0) {
                        profileLink("order history") { state.panel = .orderHistory }
                        profileLink("verify pickup") { state.panel = .nfcVerify }
                        if user.isShop == true {
                            profileLink("staff orders") { state.panel = .staff }
                        }
                    }
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

                    Divider().foregroundStyle(c.border)

                    Button {
                        state.signOut()
                    } label: {
                        Text("sign out")
                            .font(.mono(13))
                            .foregroundStyle(c.muted)
                    }

                } else {
                    Text("not signed in")
                        .font(.mono(13))
                        .foregroundStyle(c.muted)

                    Button {
                        state.panel = .auth
                    } label: {
                        Text("sign in →")
                            .font(.mono(13, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(c.text)
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
    }

    private func profileLink(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.mono(13))
                    .foregroundStyle(c.text)
                Spacer()
                Text("→")
                    .font(.mono(13))
                    .foregroundStyle(c.muted)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            }
        }
    }
}
