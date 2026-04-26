import SwiftUI

struct MembersTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isSignedIn {
                    EmptyStateView("sign in to see the member directory.")
                } else {
                    RemoteView(fetch: {
                        guard let token = Keychain.memberToken else { return [FraiseMemberPublic]() }
                        return try await APIClient.shared.fetchDirectory(token: token)
                    }) { members in
                        ScrollView {
                            FraiseCard {
                                ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                                    MemberRow(rank: i + 1, member: m, showBorder: i > 0)
                                }
                            }
                            .padding(Spacing.lg)
                        }
                    }
                }
            }
            .background(c.background)
            .navigationTitle("members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
        }
    }
}

// MARK: - MemberRow

struct MemberRow: View {
    let rank: Int
    let member: FraiseMemberPublic
    var showBorder: Bool = true
    @Environment(\.fraiseColors) var c

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(String(format: "%02d", rank))
                .font(.mono(11)).foregroundStyle(c.muted).frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                Text("since \(memberSince(member.createdAt))").font(.mono(10)).foregroundStyle(c.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(member.standing)").font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                Text("\(member.eventsAttended) attended").font(.mono(10)).foregroundStyle(c.muted)
            }
        }
        .padding(Spacing.md)
        .overlay(alignment: .top) {
            if showBorder { Rectangle().frame(height: 0.5).foregroundStyle(c.border) }
        }
    }

    private func memberSince(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return String(iso.prefix(7))
        }
        let d = DateFormatter(); d.dateFormat = "MMM yyyy"
        return d.string(from: date).lowercased()
    }
}
