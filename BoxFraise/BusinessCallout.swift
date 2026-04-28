import SwiftUI

struct BusinessCallout: View {
    @Environment(\.fraiseColors) private var c
    let business: Business
    let onSelect: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(business.name.lowercased())
                        .font(.system(size: 16, design: .serif))
                        .foregroundStyle(c.text)

                    if let neighbourhood = business.neighbourhood ?? business.displayCity.isEmpty ? nil : business.displayCity {
                        Text(neighbourhood.lowercased())
                            .font(.mono(11))
                            .foregroundStyle(c.muted)
                    }

                    if let hours = business.hours {
                        Text(hours)
                            .font(.mono(10))
                            .foregroundStyle(c.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Text("×")
                        .font(.mono(18))
                        .foregroundStyle(c.muted)
                }
            }

            if let desc = business.description {
                Text(desc)
                    .font(.mono(12))
                    .foregroundStyle(c.muted)
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                Button(action: onSelect) {
                    Text(business.isCollection ? "order →" : "view →")
                        .font(.mono(12, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(c.text)
                        .clipShape(Capsule())
                }
                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(c.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(c.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
    }
}
