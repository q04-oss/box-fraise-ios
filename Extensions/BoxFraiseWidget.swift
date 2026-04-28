import WidgetKit
import SwiftUI

// MARK: - Box Fraise Home Screen Widget
// Add this file to the Widget Extension target in Xcode (not the main app target).
// The main app writes shared data to group.com.boxfraise.app UserDefaults.

// MARK: - Timeline entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let locationName: String
    let locationCity: String
    let popupCount: Int
    let season: String
}

// MARK: - Provider

struct BoxFraiseWidgetProvider: TimelineProvider {
    private let group = UserDefaults(suiteName: "group.com.boxfraise.app")

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: .now, locationName: "Marche Atwater",
                    locationCity: "Montreal", popupCount: 2, season: "spring")
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let e = entry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [e], policy: .after(refresh)))
    }

    private func entry() -> WidgetEntry {
        WidgetEntry(
            date: .now,
            locationName: group?.string(forKey: "widget_location_name") ?? "box fraise",
            locationCity: group?.string(forKey: "widget_location_city") ?? "",
            popupCount:   group?.integer(forKey: "widget_popup_count") ?? 0,
            season:       group?.string(forKey: "widget_season") ?? "season"
        )
    }
}

// MARK: - Widget view

struct BoxFraiseWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12)
            VStack(alignment: .leading, spacing: 0) {
                Text("🍓")
                    .font(.system(size: family == .systemSmall ? 22 : 28))
                Spacer()
                if family != .systemSmall {
                    Text(entry.season.lowercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.bottom, 4)
                }
                Text(entry.locationName.lowercased())
                    .font(.system(family == .systemSmall ? .footnote : .subheadline, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !entry.locationCity.isEmpty {
                    Text(entry.locationCity.lowercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                if entry.popupCount > 0 {
                    Text("\(entry.popupCount) popup\(entry.popupCount == 1 ? "" : "s")")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Widget declaration

struct BoxFraiseWidget: Widget {
    let kind = "BoxFraiseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoxFraiseWidgetProvider()) { entry in
            BoxFraiseWidgetView(entry: entry)
                .containerBackground(Color(red: 0.11, green: 0.11, blue: 0.12), for: .widget)
        }
        .configurationDisplayName("Box Fraise")
        .description("Nearest location and active popups.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget bundle (entry point for the extension)

@main
struct BoxFraiseWidgetBundle: WidgetBundle {
    var body: some Widget {
        BoxFraiseWidget()
        if #available(iOS 16.2, *) {
            BoxFraiseOrderLiveActivity()
        }
    }
}
