import SwiftUI

struct StandingOrdersPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var orders: [StandingOrder] = []
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FraiseBackButton { state.panel = .profile }
                Spacer()
                Text("standing orders")
                    .font(.system(size: 14, design: .serif)).foregroundStyle(c.text)
                Spacer()
                if state.user?.verified == true && !creating {
                    Button { withAnimation { creating = true } } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(c.muted)
                    }
                } else {
                    Color.clear.frame(width: 24)
                }
            }
            .padding(.horizontal, Spacing.md).padding(.vertical, 14)

            Divider().foregroundStyle(c.border).opacity(0.6)

            if state.user?.verified != true {
                unverifiedView
            } else if creating {
                CreateStandingOrderView(onCancel: { withAnimation { creating = false } }) { order in
                    orders.insert(order, at: 0)
                    withAnimation { creating = false }
                }
            } else if loading {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { _ in FraiseSkeletonRow(wide: true) }
                    }.padding(Spacing.md)
                }
            } else if let err = error {
                FraiseEmptyState(icon: "exclamationmark.circle", title: "couldn't load", subtitle: err)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if orders.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(orders) { order in
                            StandingOrderCard(order: order) { updated in
                                if updated.status == "cancelled" {
                                    orders.removeAll { $0.id == updated.id }
                                } else {
                                    orders = orders.map { $0.id == updated.id ? updated : $0 }
                                }
                            }
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
        .task { await load() }
    }

    private var unverifiedView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FraiseEmptyState(
                icon: "arrow.clockwise.circle",
                title: "not yet unlocked",
                subtitle: "standing orders unlock after your first box fraise pickup."
            )
            Button { state.panel = .nfcVerify } label: {
                HStack {
                    Text("verify pickup").font(.mono(13, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                .background(c.text).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, Spacing.lg)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FraiseEmptyState(
                icon: "arrow.clockwise.circle",
                title: "no standing orders",
                subtitle: "set up a repeat order and we'll notify you when each batch is ready."
            )
            Button { withAnimation { creating = true } } label: {
                HStack {
                    Text("set up a standing order")
                        .font(.mono(13, weight: .medium)).foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                .background(c.text).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, Spacing.lg)
    }

    @MainActor private func load() async {
        guard let token = Keychain.userToken, state.user?.verified == true else { return }
        loading = true; error = nil
        do {
            orders = try await APIClient.shared.fetchStandingOrders(token: token)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Standing order card

struct StandingOrderCard: View {
    @Environment(\.fraiseColors) private var c
    let order: StandingOrder
    let onUpdate: (StandingOrder) -> Void
    @State private var inFlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(order.isActive ? c.text : c.border)
                    .frame(width: 3).padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    if let variety = order.varietyName {
                        Text(variety.lowercased())
                            .font(.system(size: 16, design: .serif)).foregroundStyle(c.text)
                    }
                    Text([order.chocolate, order.finish, "×\(order.quantity)"]
                        .joined(separator: " · ").lowercased())
                        .font(.mono(11)).foregroundStyle(c.muted)
                    if let loc = order.locationName {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin").font(.system(size: 9)).foregroundStyle(c.muted)
                            Text(loc.lowercased()).font(.mono(10)).foregroundStyle(c.muted)
                        }
                    }
                }
                Spacer()
                Text(order.status)
                    .font(.mono(9)).foregroundStyle(order.isActive ? c.text : c.muted)
                    .tracking(1).textCase(.uppercase)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((order.isActive ? c.text : c.border).opacity(0.1))
                    .clipShape(Capsule())
            }
            .padding(Spacing.md)

            Divider().foregroundStyle(c.border).opacity(0.6)

            HStack(spacing: 0) {
                actionButton(
                    order.isActive ? "pause" : "resume",
                    color: c.muted
                ) { await update(status: order.isActive ? "paused" : "active") }

                Divider().frame(width: 0.5).foregroundStyle(c.border)

                actionButton("cancel", color: Color(hex: "C0392B")) {
                    await update(status: "cancelled")
                }
            }
            .frame(height: 44)
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(c.border, lineWidth: 0.5))
        .disabled(inFlight)
    }

    private func actionButton(_ label: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button {
            guard !inFlight else { return }
            inFlight = true
            Task { @MainActor in
                await action()
                inFlight = false
            }
        } label: {
            Text(inFlight ? "—" : label)
                .font(.mono(11, weight: .medium)).foregroundStyle(color)
                .frame(maxWidth: .infinity)
        }
    }

    @MainActor private func update(status: String) async {
        guard let token = Keychain.userToken else { return }
        do {
            try await APIClient.shared.updateStandingOrder(id: order.id, status: status, token: token)
            // Build updated model since PATCH returns OKResponse not the full model
            let updated = StandingOrder(
                id: order.id, varietyName: order.varietyName, locationName: order.locationName,
                quantity: order.quantity, chocolate: order.chocolate, finish: order.finish,
                status: status
            )
            onUpdate(updated)
        } catch {}
    }
}

// MARK: - Create form

struct CreateStandingOrderView: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let onCancel: () -> Void
    let onCreated: (StandingOrder) -> Void

    @State private var selectedVarietyId: Int?
    @State private var selectedVarietyName: String?
    @State private var selectedLocationId: Int?
    @State private var selectedLocationName: String?
    @State private var quantity = 4
    @State private var chocolate = "dark"
    @State private var finish = "plain"
    @State private var loading = false
    @State private var error: String?

    private var collections: [Business] {
        state.approvedBusinesses.filter { $0.isCollection }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack {
                    Button(action: onCancel) {
                        Text("cancel").font(.mono(12)).foregroundStyle(c.muted)
                    }
                    Spacer()
                    Text("new standing order")
                        .font(.system(size: 13, design: .serif)).foregroundStyle(c.text)
                    Spacer()
                    Color.clear.frame(width: 40)
                }

                // Variety
                VStack(alignment: .leading, spacing: 8) {
                    FraiseSectionLabel(text: "strawberry")
                    ForEach(state.varieties) { v in
                        selectionRow(v.name, subtitle: v.description ?? "",
                                     trailing: v.priceFormatted,
                                     selected: selectedVarietyId == v.id) {
                            selectedVarietyId = v.id
                            selectedVarietyName = v.name
                        }
                    }
                }

                // Location
                VStack(alignment: .leading, spacing: 8) {
                    FraiseSectionLabel(text: "node")
                    ForEach(collections) { loc in
                        selectionRow(loc.name,
                                     subtitle: loc.neighbourhood ?? loc.displayCity,
                                     trailing: "", selected: selectedLocationId == loc.id) {
                            selectedLocationId = loc.id
                            selectedLocationName = loc.name
                        }
                    }
                }

                // Quantity
                HStack {
                    FraiseSectionLabel(text: "quantity")
                    Spacer()
                    HStack(spacing: 20) {
                        Button { if quantity > 1 { quantity -= 1 } } label: {
                            Image(systemName: "minus").font(.system(size: 13, weight: .medium))
                                .foregroundStyle(c.text).frame(width: 32, height: 32)
                                .background(c.card).clipShape(Circle())
                                .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                        }
                        Text("\(quantity)").font(.mono(18, weight: .medium)).foregroundStyle(c.text)
                            .frame(minWidth: 24, alignment: .center)
                        Button { if quantity < 12 { quantity += 1 } } label: {
                            Image(systemName: "plus").font(.system(size: 13, weight: .medium))
                                .foregroundStyle(c.text).frame(width: 32, height: 32)
                                .background(c.card).clipShape(Circle())
                                .overlay(Circle().strokeBorder(c.border, lineWidth: 0.5))
                        }
                    }
                }

                // Chocolate
                VStack(alignment: .leading, spacing: 8) {
                    FraiseSectionLabel(text: "chocolate")
                    ForEach(CHOCOLATES, id: \.id) { opt in
                        selectionRow(opt.name, subtitle: "", trailing: "",
                                     selected: chocolate == opt.id) { chocolate = opt.id }
                    }
                }

                // Finish
                VStack(alignment: .leading, spacing: 8) {
                    FraiseSectionLabel(text: "finish")
                    ForEach(FINISHES, id: \.id) { opt in
                        selectionRow(opt.name, subtitle: "", trailing: "",
                                     selected: finish == opt.id) { finish = opt.id }
                    }
                }

                if let error {
                    Text(error).font(.mono(11)).foregroundStyle(Color(hex: "C0392B"))
                }

                Button {
                    guard selectedVarietyId != nil, selectedLocationId != nil else { return }
                    Task { await submit() }
                } label: {
                    HStack {
                        if loading { ProgressView().tint(.white) }
                        Text(loading ? "—" : "save standing order")
                            .font(.mono(13, weight: .medium)).foregroundStyle(.white)
                        if !loading { Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Spacing.md).padding(.vertical, 16)
                    .background(selectedVarietyId != nil && selectedLocationId != nil ? c.text : c.border)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(loading || selectedVarietyId == nil || selectedLocationId == nil)
            }
            .padding(Spacing.md)
        }
    }

    private func selectionRow(_ title: String, subtitle: String, trailing: String,
                               selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.mono(14)).foregroundStyle(c.text)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.mono(11)).foregroundStyle(c.muted).lineLimit(1)
                    }
                }
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing).font(.mono(13)).foregroundStyle(c.muted)
                }
                ZStack {
                    Circle().fill(selected ? c.text : Color.clear).frame(width: 20, height: 20)
                    Circle().strokeBorder(selected ? c.text : c.border, lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                }
            }
            .padding(Spacing.md)
            .background(selected ? c.card : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? c.border : c.border.opacity(0.5), lineWidth: 0.5))
        }
    }

    @MainActor private func submit() async {
        guard let token = Keychain.userToken,
              let varId = selectedVarietyId,
              let locId = selectedLocationId else { return }
        loading = true; error = nil
        do {
            let created = try await APIClient.shared.createStandingOrder(
                varietyId: varId, locationId: locId,
                quantity: quantity, chocolate: chocolate, finish: finish, token: token
            )
            let withNames = StandingOrder(
                id: created.id,
                varietyName: created.varietyName ?? selectedVarietyName,
                locationName: created.locationName ?? selectedLocationName,
                quantity: created.quantity, chocolate: created.chocolate,
                finish: created.finish, status: created.status
            )
            Haptics.notification(.success)
            onCreated(withNames)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
