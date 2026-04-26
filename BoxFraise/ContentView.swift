import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @State private var selectedTab: Tab = .discover

    enum Tab: String, CaseIterable {
        case discover, members, claims, account
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DiscoverTab()
                .tabItem { Label("discover", systemImage: "house") }
                .tag(Tab.discover)

            MembersTab()
                .tabItem { Label("members", systemImage: "person.2") }
                .tag(Tab.members)

            InvitationsTab()
                .tabItem { Label("claims", systemImage: "envelope") }
                .tag(Tab.claims)
                .badge(appState.pendingInvitations.count > 0 ? appState.pendingInvitations.count : 0)

            AccountTab()
                .tabItem { Label("account", systemImage: "person") }
                .tag(Tab.account)
        }
        .tint(c.text)
        .onChange(of: appState.pendingScreen) { _, screen in
            guard let screen else { return }
            switch screen {
            case "my-claims": selectedTab = .claims
            case "home":      selectedTab = .discover
            default:          break
            }
            appState.pendingScreen = nil
        }
    }
}
