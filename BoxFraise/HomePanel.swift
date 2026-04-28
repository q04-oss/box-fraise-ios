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
            if let loc = state.activeLocation, loc.isApproved {
                // Location selected strip
                Button {
                    state.clearLocation()
                } label: {
                    Text(loc.name.lowercased())
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(c.text)
                        .tracking(0.3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else {
                // Search row
                HStack(spacing: 10) {
                    HStack {
                        TextField("for better taste", text: $searchQuery)
                            .font(.mono(14))
                            .foregroundStyle(c.text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(c.searchBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))

                    Button {
                        // fraise.chat — placeholder
                    } label: {
                        Text("🍓")
                            .font(.system(size: 17))
                            .frame(width: 42, height: 42)
                            .background(c.searchBg)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }

            Divider().foregroundStyle(c.border).opacity(0.6)

            if searchQuery.isEmpty {
                // Ambient discover view
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
                            Button {
                                state.panel = .popups
                            } label: {
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
                            Button {
                                state.selectLocation(nearest)
                            } label: {
                                Text("\(nearest.name.lowercased())  →")
                                    .font(.system(size: 14, design: .serif))
                                    .foregroundStyle(c.text)
                            }
                            .padding(.top, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .padding(.top, 8)

                    Spacer(minLength: 40)
                }
            } else {
                // Search results
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
        .overlay(alignment: .topTrailing) {
            // Profile button
            Button {
                state.panel = state.isSignedIn ? .profile : .auth
            } label: {
                Circle()
                    .strokeBorder(c.border, lineWidth: 0.5)
                    .background(Circle().fill(c.searchBg))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(state.user?.displayName?.prefix(1).uppercased() ?? "·")
                            .font(.mono(12, weight: .medium))
                            .foregroundStyle(c.muted)
                    )
            }
            .padding(.trailing, Spacing.md)
            .padding(.top, 12)
        }
    }
}
