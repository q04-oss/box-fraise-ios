import SwiftUI

struct PartnerDetailPanel: View {
    @Environment(AppState.self)  private var state
    @Environment(\.fraiseColors) private var c
    let business: Business
    @State private var memoriesCount: Int?
    @State private var drinksStore:   VenueDrinksStore
    @State private var showCart = false

    init(business: Business) {
        self.business   = business
        _drinksStore    = State(initialValue: VenueDrinksStore(business: business))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    FraiseBackButton { state.navigate(to: .home) }

                    // ── Identity ──────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("example")
                            .font(.mono(9)).foregroundStyle(c.muted)
                            .tracking(1.5).textCase(.uppercase)

                        Text(business.name.lowercased())
                            .font(.system(size: 28, design: .serif)).foregroundStyle(c.text)

                        if let neighbourhood = business.neighbourhood ?? business.displayCity {
                            Text(neighbourhood.lowercased())
                                .font(.mono(12)).foregroundStyle(c.muted)
                        }
                        if let count = memoriesCount, count > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9)).foregroundStyle(c.muted)
                                Text("\(count) \(count == 1 ? "memory" : "memories") made here")
                                    .font(.mono(10)).foregroundStyle(c.muted)
                            }
                        }
                    }

                    // ── Description ───────────────────────────────────────────
                    if let desc = business.description {
                        Text(desc)
                            .font(.mono(13)).foregroundStyle(c.muted).lineSpacing(4)
                    }

                    // ── Hours + address ───────────────────────────────────────
                    if business.hours != nil || business.address != nil {
                        VStack(spacing: 0) {
                            if let hours = business.hours   { detailRow("hours",   value: hours) }
                            if let addr  = business.address { detailRow("address", value: addr)  }
                        }
                        .background(c.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
                    }

                    // ── Loyalty inline prompt ─────────────────────────────────
                    if state.user != nil {
                        LoyaltyInlineView(business: business)
                    }

                    // ── Drink menu ────────────────────────────────────────────
                    if state.user != nil {
                        drinkMenuSection
                    }

                    // ── Node info ─────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("not yet a node")
                                .font(.mono(9)).foregroundStyle(c.muted).tracking(1.5)
                            Text("box fraise nodes host pickups — we deliver fresh strawberries here when an order threshold is met. the business doesn't stock anything between deliveries.")
                                .font(.mono(11)).foregroundStyle(c.muted).lineSpacing(4)
                        }

                        if let email = URL(string: "mailto:hello@fraise.box?subject=Nominate%20\(business.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? business.name)&body=I%27d%20like%20to%20nominate%20this%20location%20as%20a%20Box%20Fraise%20node.") {
                            Link(destination: email) {
                                HStack {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 12)).foregroundStyle(c.muted)
                                    Text("nominate as a node")
                                        .font(.mono(12)).foregroundStyle(c.text)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11)).foregroundStyle(c.border)
                                }
                                .padding(.horizontal, Spacing.md).padding(.vertical, 13)
                                .background(c.card)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
                            }
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                // Extra bottom padding so the cart bar never occludes the last row.
                .padding(.bottom, drinksStore.cartCount > 0 ? 80 : 0)
            }
            .scrollIndicators(.hidden)

            // ── Cart bar ──────────────────────────────────────────────────────
            if drinksStore.cartCount > 0 {
                Button { showCart = true } label: {
                    HStack {
                        Text("\(drinksStore.cartCount) item\(drinksStore.cartCount == 1 ? "" : "s")")
                            .font(.mono(13)).foregroundStyle(c.background)
                        Spacer()
                        Text(drinksStore.cartTotalCents.formattedPrice)
                            .font(.mono(13)).foregroundStyle(c.background.opacity(0.7))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(c.background.opacity(0.7))
                    }
                    .padding(.horizontal, Spacing.md).padding(.vertical, 14)
                    .background(c.text)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, 12)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.fraiseSpring, value: drinksStore.cartCount > 0)
        .sheet(isPresented: $showCart) {
            CartSheet(business: business, store: drinksStore)
        }
        .task {
            if let id = business.locationId {
                memoriesCount = (try? await APIClient.shared.fetchBusinessDateStats(businessId: id))?.memoriesCount
            }
            await drinksStore.loadMenu()
        }
    }

    // MARK: - Drink menu section

    @ViewBuilder
    private var drinkMenuSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("menu")
                .font(.mono(9)).foregroundStyle(c.muted)
                .tracking(1.5).textCase(.uppercase)
                .padding(.bottom, Spacing.sm)

            if drinksStore.isLoading {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonBlock(height: 56) }
                }
            } else if drinksStore.menu.isEmpty {
                Text("no drinks available")
                    .font(.mono(12)).foregroundStyle(c.muted)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: 0) {
                    ForEach(drinksStore.menu) { drink in
                        DrinkRow(
                            drink: drink,
                            qty: drinksStore.cart[drink.id] ?? 0
                        ) { delta in
                            if delta > 0 { drinksStore.add(drink) }
                            else         { drinksStore.remove(drink) }
                        }
                        if drink.id != drinksStore.menu.last?.id {
                            Divider().padding(.leading, Spacing.md).opacity(Divide.row)
                        }
                    }
                }
                .background(c.card)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(c.border, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Detail row

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.mono(10)).foregroundStyle(c.muted)
                .tracking(1).textCase(.uppercase)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.mono(12)).foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md).padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }
}
