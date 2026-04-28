import SwiftUI

struct PartnerDetailPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let business: Business

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                FraiseBackButton { state.panel = .home }

                VStack(alignment: .leading, spacing: 6) {
                    Text("example")
                        .font(.mono(9))
                        .foregroundStyle(c.muted)
                        .tracking(1.5)
                        .textCase(.uppercase)

                    Text(business.name.lowercased())
                        .font(.system(size: 28, design: .serif))
                        .foregroundStyle(c.text)

                    if let neighbourhood = business.neighbourhood ?? (business.displayCity.isEmpty ? nil : business.displayCity) {
                        Text(neighbourhood.lowercased())
                            .font(.mono(12))
                            .foregroundStyle(c.muted)
                    }
                }

                if let desc = business.description {
                    Text(desc)
                        .font(.mono(13))
                        .foregroundStyle(c.muted)
                        .lineSpacing(4)
                }

                if business.hours != nil || business.address != nil {
                    VStack(spacing: 0) {
                        if let hours = business.hours {
                            detailRow("hours", value: hours)
                        }
                        if let address = business.address {
                            detailRow("address", value: address)
                        }
                    }
                    .background(c.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(c.border, lineWidth: 0.5))
                }

                Text("this business is not yet on box fraise.")
                    .font(.mono(11))
                    .foregroundStyle(c.muted)
                    .padding(.top, Spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.mono(10))
                .foregroundStyle(c.muted)
                .tracking(1)
                .textCase(.uppercase)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.mono(12))
                .foregroundStyle(c.text)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 0.5).foregroundStyle(c.border)
        }
    }
}
