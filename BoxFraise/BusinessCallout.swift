import SwiftUI
import CoreLocation

struct BusinessCallout: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    let business: Business
    let onSelect: () -> Void
    let onDismiss: () -> Void

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

            // ── Header ────────────────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(business.name.lowercased())
                        .font(.system(size: 20, design: .serif))
                        .foregroundStyle(c.text)

                    HStack(spacing: 6) {
                        if let place = business.neighbourhood ?? (business.displayCity.isEmpty ? nil : business.displayCity) {
                            Text(place.lowercased())
                                .font(.mono(11)).foregroundStyle(c.muted).tracking(0.3)
                        }
                        if let dist = distanceLabel {
                            Text("·").font(.mono(11)).foregroundStyle(c.border)
                            Text(dist).font(.mono(11)).foregroundStyle(c.muted)
                        }
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.muted)
                        .frame(width: 28, height: 28)
                        .background(c.searchBg)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // ── Meta row ──────────────────────────────────────────────────────
            if business.hours != nil || business.description != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let hours = business.hours {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(c.muted)
                            Text(hours.lowercased())
                                .font(.mono(11))
                                .foregroundStyle(c.muted)
                                .lineLimit(1)
                        }
                    }
                    if let desc = business.description {
                        Text(desc.lowercased())
                            .font(.mono(12))
                            .foregroundStyle(c.muted)
                            .lineSpacing(3)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)
            }

            // ── CTA ───────────────────────────────────────────────────────────
            Divider().foregroundStyle(c.border).opacity(0.6)

            Button(action: onSelect) {
                HStack {
                    Text(business.isCollection ? "order" : "view")
                        .font(.mono(13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 14)
                .background(c.text)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(c.border.opacity(0.4), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 6)
    }
}
