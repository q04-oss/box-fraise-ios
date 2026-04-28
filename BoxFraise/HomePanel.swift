import SwiftUI
import CoreLocation

struct HomePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var searchQuery = ""
    @State private var recentSearches: [String] = []
    @State private var pendingAkeneInvitation: AkeneInvitation?
    @State private var pendingDateInvitation: DateInvitation?

    private var approvedPartnerCount: Int {
        state.approvedBusinesses.filter { $0.type == "partner" }.count
    }

    private var dateLabel: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased()
    }

    private var season: String {
        let m = Calendar.current.component(.month, from: Date())
        switch m {
        case 3...5:  return "spring"
        case 6...8:  return "summer"
        case 9...11: return "autumn"
        default:     return "winter"
        }
    }

    private var searchResults: [Business] {
        let q = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return state.approvedBusinesses.filter {
            $0.name.lowercased().contains(q) ||
            ($0.neighbourhood ?? "").lowercased().contains(q) ||
            ($0.city ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Search pill + profile button ──────────────────────────────────
            HStack(spacing: 10) {
                if let loc = state.activeLocation, loc.isApproved {
                    Button { state.clearLocation() } label: {
                        HStack {
                            Text(loc.name.lowercased())
                                .font(.system(size: 14, design: .serif))
                                .foregroundStyle(c.text)
                                .tracking(0.3)
                            Spacer()
                            Text("×")
                                .font(.mono(16))
                                .foregroundStyle(c.muted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(c.searchBg)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(c.border, lineWidth: 0.5))
                    }
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(c.muted)
                        TextField("search", text: $searchQuery)
                            .font(.mono(14))
                            .foregroundStyle(c.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchQuery.isEmpty {
                            Button { searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(c.muted)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(c.searchBg)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(c.border, lineWidth: 0.5))
                }

                // Profile button
                Button {
                    state.panel = state.isSignedIn ? .profile : .auth
                } label: {
                    Circle()
                        .fill(c.searchBg)
                        .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Text(state.user?.displayName?.prefix(1).uppercased() ?? "·")
                                .font(.mono(13, weight: .medium))
                                .foregroundStyle(c.muted)
                        )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // ── Content ───────────────────────────────────────────────────────
            if searchQuery.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateLabel)
                            .font(.system(size: 32, design: .serif))
                            .foregroundStyle(c.text)

                        Text(season)
                            .font(.mono(11))
                            .foregroundStyle(c.muted)
                            .tracking(1)

                        HStack(spacing: 0) {
                            Text("\(approvedPartnerCount) locations · ")
                                .font(.mono(10))
                                .foregroundStyle(c.muted)
                                .tracking(1)
                            Button { state.panel = .popups } label: {
                                Text("popups")
                                    .font(.mono(10))
                                    .foregroundStyle(c.muted)
                                    .tracking(1)
                            }
                            Text(" · edmonton")
                                .font(.mono(10))
                                .foregroundStyle(c.muted)
                                .tracking(1)
                        }
                        .padding(.top, 2)

                        if let active = state.activeOrder {
                            ActiveOrderCard(order: active) {
                                state.panel = .orderHistory
                            }
                            .padding(.top, 12)
                        }

                        // Date night takes priority — it's time-sensitive
                        if let inv = pendingDateInvitation {
                            DateNightCard(invitation: inv) {
                                state.panel = .messages
                            }
                            .padding(.top, 12)
                        } else if let inv = pendingAkeneInvitation {
                            AkenePendingCard(invitation: inv) {
                                state.panel = .akene
                            }
                            .padding(.top, 12)
                        }

                        if state.businesses.isEmpty {
                            VStack(spacing: 10) {
                                FraiseSkeletonRow(wide: true)
                                FraiseSkeletonRow()
                                FraiseSkeletonRow(wide: true)
                            }
                            .padding(.top, 12)
                        } else if let nearest = state.nearestCollection {
                            NearestCard(business: nearest) {
                                state.selectLocation(nearest)
                            }
                            .padding(.top, 12)
                        }

                        if !recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("recent")
                                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                                    .padding(.bottom, 4)
                                    .padding(.top, Spacing.lg)
                                ForEach(recentSearches, id: \.self) { q in
                                    Button { searchQuery = q } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "clock")
                                                .font(.system(size: 11)).foregroundStyle(c.muted)
                                            Text(q).font(.mono(13)).foregroundStyle(c.text)
                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                    }
                                    if q != recentSearches.last {
                                        Divider().foregroundStyle(c.border).opacity(Divide.row)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .padding(.top, 4)

                    Spacer(minLength: 40)
                }
                .refreshable { await state.refresh() }
            } else {
                if searchResults.isEmpty {
                    VStack {
                        Text("nothing matched — try a neighbourhood or name")
                            .font(.mono(12))
                            .foregroundStyle(c.muted)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { biz in
                                Button {
                                    saveRecentSearch(searchQuery)
                                    searchQuery = ""
                                    state.selectLocation(biz)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(biz.name)
                                                .font(.mono(14))
                                                .foregroundStyle(c.text)
                                            if let n = biz.neighbourhood ?? biz.city {
                                                Text(n)
                                                    .font(.mono(11))
                                                    .foregroundStyle(c.muted)
                                            }
                                        }
                                        Spacer()
                                        Text("→")
                                            .font(.mono(13))
                                            .foregroundStyle(c.muted)
                                    }
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 14)
                                }
                                Divider().padding(.leading, Spacing.md).foregroundStyle(c.border)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            recentSearches = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
        }
        .task {
            guard let token = Keychain.userToken else { return }
            async let akene = try? await APIClient.shared.fetchAkeneInvitations(token: token)
            async let dates = try? await APIClient.shared.fetchDateInvitations(token: token)
            if let v = await akene { pendingAkeneInvitation = v.first { $0.isPending } }
            if let v = await dates { pendingDateInvitation = v.first { $0.isPending } }
        }
    }

    private func saveRecentSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: "recentSearches") ?? []
        list.removeAll { $0 == q }
        list.insert(q, at: 0)
        if list.count > 3 { list = Array(list.prefix(3)) }
        UserDefaults.standard.set(list, forKey: "recentSearches")
        recentSearches = list
    }
}

// MARK: - Active Order Card

private struct ActiveOrderCard: View {
    @Environment(\.fraiseColors) private var c
    let order: PastOrder
    let action: () -> Void

    private var statusColor: Color {
        order.isReady ? Color.fraiseBlue : c.muted
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(statusColor).frame(width: 3)

                VStack(alignment: .leading, spacing: 3) {
                    Text(order.varietyName.lowercased())
                        .font(.system(size: 15, design: .serif)).foregroundStyle(c.text)
                    Text(order.isReady ? "ready for collection" : "paid · awaiting batch")
                        .font(.mono(10)).foregroundStyle(statusColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.border)
            }
            .padding(Spacing.md)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                order.isReady ? Color.fraiseBlue.opacity(0.4) : c.border,
                lineWidth: 0.5))
        }
    }
}

// MARK: - Date night card

private struct DateNightCard: View {
    @Environment(\.fraiseColors) private var c
    let invitation: DateInvitation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.text).frame(width: 40, height: 40)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14)).foregroundStyle(c.background)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("dinner invitation")
                            .font(.mono(12, weight: .medium)).foregroundStyle(c.text)
                        if invitation.isUnopened {
                            Text("earn CA$\(invitation.feeCents / 100)")
                                .font(.mono(8)).foregroundStyle(c.background)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.fraiseGreen).clipShape(Capsule())
                        }
                    }
                    if let biz = invitation.businessName {
                        Text(biz.lowercased())
                            .font(.system(size: 13, design: .serif)).foregroundStyle(c.muted)
                    }
                    Text(FraiseDateFormatter.short(invitation.eventDate))
                        .font(.mono(9)).foregroundStyle(c.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.border)
            }
            .padding(Spacing.md)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(c.text.opacity(0.2), lineWidth: 0.5))
        }
    }

}

// MARK: - Akène pending invitation card

private struct AkenePendingCard: View {
    @Environment(\.fraiseColors) private var c
    let invitation: AkeneInvitation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(c.text).frame(width: 40, height: 40)
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15)).foregroundStyle(c.background)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("you've been invited")
                        .font(.mono(12, weight: .medium)).foregroundStyle(c.text)
                    Text(invitation.title.lowercased())
                        .font(.system(size: 13, design: .serif)).foregroundStyle(c.muted)
                    if let exp = invitation.expiresAt {
                        Text(expiryLabel(exp))
                            .font(.mono(9)).foregroundStyle(c.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(c.border)
            }
            .padding(Spacing.md)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(c.text.opacity(0.2), lineWidth: 0.5))
        }
    }

    private func expiryLabel(_ iso: String) -> String {
        guard let date = FraiseDateFormatter.date(from: iso) else { return "" }
        let hours = Int(date.timeIntervalSinceNow / 3600)
        if hours <= 0 { return "expired" }
        return hours < 24 ? "\(hours)h to respond" : "\(hours / 24)d to respond"
    }
}

// MARK: - Nearest Collection Card

private struct NearestCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let business: Business
    let action: () -> Void

    private var distanceLabel: String? {
        guard let userLoc = state.userLocation, let coord = business.coordinate else { return nil }
        let metres = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
            .distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
        return metres < 1000
            ? "\(Int(metres.rounded())) m"
            : String(format: "%.1f km", metres / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("nearest")
                    .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                Text(business.name.lowercased())
                    .font(.system(size: 18, design: .serif)).foregroundStyle(c.text)
                HStack(spacing: 6) {
                    if let sub = business.neighbourhood ?? business.city {
                        Text(sub.lowercased()).font(.mono(11)).foregroundStyle(c.muted)
                    }
                    if let dist = distanceLabel {
                        Text("·").font(.mono(11)).foregroundStyle(c.border)
                        Text(dist).font(.mono(11)).foregroundStyle(c.muted)
                    }
                }
            }
            .padding(Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            Button(action: action) {
                HStack {
                    Text("order")
                        .font(.mono(13, weight: .medium)).foregroundStyle(c.text)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(c.muted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
            }
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
    }
}
