import SwiftUI

struct HomePanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var searchQuery = ""

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

                        if let nearest = state.nearestCollection {
                            Button { state.selectLocation(nearest) } label: {
                                Text("\(nearest.name.lowercased())  →")
                                    .font(.system(size: 14, design: .serif))
                                    .foregroundStyle(c.text)
                            }
                            .padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .padding(.top, 4)

                    Spacer(minLength: 40)
                }
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
    }
}
