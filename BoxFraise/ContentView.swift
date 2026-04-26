import SwiftUI

private struct TabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @State private var tab: Tab = .hold
    @State private var tabBarHeight: CGFloat = 0

    enum Tab { case hold, invited }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Both tabs stay in memory — opacity switch avoids reload on tab change
            Group {
                HoldTab()    .opacity(tab == .hold    ? 1 : 0)
                InvitationsTab().opacity(tab == .invited ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: tabBarHeight) }

            tabBar
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TabBarHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .ignoresSafeArea(edges: .bottom)
        .background(c.background)
        .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
        .onChange(of: appState.pendingScreen) { _, screen in
            guard let screen else { return }
            tab = (screen == "my-claims") ? .invited : .hold
            appState.pendingScreen = nil
        }
    }

    // MARK: - Custom tab bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
            HStack {
                tabButton("hold", .hold)
                Spacer()
                invitedButton
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, 14)
            .padding(.bottom, 34)
        }
        .background(c.background)
    }

    private func tabButton(_ label: String, _ t: Tab) -> some View {
        Button(label) { tab = t }
            .font(.mono(11))
            .foregroundStyle(tab == t ? c.text : c.muted)
            .tracking(1.5)
    }

    private var invitedButton: some View {
        let count = appState.pendingInvitations.count
        return Button { tab = .invited } label: {
            HStack(spacing: 6) {
                Text("invited")
                    .font(.mono(11))
                    .foregroundStyle(tab == .invited ? c.text : c.muted)
                    .tracking(1.5)
                if count > 0 {
                    Text("\(count)")
                        .font(.mono(9))
                        .foregroundStyle(c.background)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(c.text).clipShape(Capsule())
                }
            }
        }
    }
}
