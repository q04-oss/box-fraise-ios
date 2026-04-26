import SwiftUI

struct MembersTab: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c

    @State private var members: [FraiseMemberPublic] = []
    @State private var loading = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if !appState.isSignedIn {
                    emptyState("sign in to see the member directory.")
                } else if loading && members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    emptyState(error)
                } else if members.isEmpty {
                    emptyState("no members yet.")
                } else {
                    list
                }
            }
            .background(c.background)
            .navigationTitle("members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(c.background, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                FraiseCard {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        MemberRow(rank: index + 1, member: member, showBorder: index > 0)
                    }
                }
            }
            .padding(Spacing.lg)
        }
    }

    private func load() async {
        guard appState.isSignedIn, let token = Keychain.memberToken else { return }
        loading = true
        error = nil
        do {
            members = try await APIClient.shared.fetchDirectory(token: token)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.mono(13))
                .foregroundStyle(c.muted)
            Spacer()
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
                .font(.mono(11))
                .foregroundStyle(c.muted)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.mono(13, weight: .medium))
                    .foregroundStyle(c.text)
                Text("since \(memberSince(member.createdAt))")
                    .font(.mono(10))
                    .foregroundStyle(c.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(member.standing)")
                    .font(.mono(13, weight: .medium))
                    .foregroundStyle(c.text)
                Text("\(member.eventsAttended) attended")
                    .font(.mono(10))
                    .foregroundStyle(c.muted)
            }
        }
        .padding(Spacing.md)
        .overlay(alignment: .top) {
            if showBorder {
                Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            }
        }
    }

    private func memberSince(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return iso.prefix(7).description
        }
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return display.string(from: date).lowercased()
    }
}
