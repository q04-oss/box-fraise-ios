import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Activity Attributes
// Add this file to the Widget Extension target in Xcode (not the main app target).

public struct BoxFraiseOrderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String       // "paid" | "preparing" | "ready" | "collected"
        public var statusLabel: String
    }

    public let orderId: Int
    public let varietyName: String
    public let locationName: String
}

// MARK: - Lock Screen / Notification Banner

struct OrderLockScreenView: View {
    let context: ActivityViewContext<BoxFraiseOrderAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Text("🍓").font(.system(size: 26))
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.varietyName.lowercased())
                    .font(.system(.subheadline, design: .serif))
                Text(context.attributes.locationName.lowercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(context.state.statusLabel)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                OrderProgressBar(status: context.state.status)
                    .frame(width: 60)
            }
        }
        .padding()
    }
}

// MARK: - Dynamic Island

@available(iOS 16.2, *)
struct BoxFraiseOrderLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BoxFraiseOrderAttributes.self) { context in
            OrderLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.11, green: 0.11, blue: 0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("🍓").font(.system(size: 20)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.statusLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.varietyName.lowercased())
                            .font(.system(.footnote, design: .serif))
                        OrderProgressBar(status: context.state.status)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                Text("🍓").font(.system(size: 14))
            } compactTrailing: {
                Text(context.state.statusLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            } minimal: {
                Text("🍓").font(.system(size: 12))
            }
        }
    }
}

// MARK: - Progress bar

struct OrderProgressBar: View {
    let status: String
    private let steps = ["paid", "preparing", "ready", "collected"]

    private var progress: CGFloat {
        CGFloat((steps.firstIndex(of: status) ?? 0) + 1) / CGFloat(steps.count)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(height: 3)
                Capsule().fill(Color.white.opacity(0.8)).frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Main app helpers
// Import ActivityKit in your main app target and call these from AppState or OrderPanel.

@available(iOS 16.2, *)
public func startOrderLiveActivity(orderId: Int, varietyName: String, locationName: String) {
    let attrs = BoxFraiseOrderAttributes(
        orderId: orderId, varietyName: varietyName, locationName: locationName
    )
    let state = BoxFraiseOrderAttributes.ContentState(status: "paid", statusLabel: "paid")
    _ = try? Activity<BoxFraiseOrderAttributes>.request(
        attributes: attrs,
        content: ActivityContent(state: state, staleDate: .distantFuture),
        pushType: nil
    )
}

@available(iOS 16.2, *)
public func updateOrderLiveActivity(orderId: Int, status: String) {
    let label = status.replacingOccurrences(of: "_", with: " ")
    let state = BoxFraiseOrderAttributes.ContentState(status: status, statusLabel: label)
    let content = ActivityContent(state: state, staleDate: .distantFuture)
    Task {
        for activity in Activity<BoxFraiseOrderAttributes>.activities
            where activity.attributes.orderId == orderId {
            await activity.update(content)
            if status == "collected" {
                await activity.end(content, dismissalPolicy: .after(.now + 300))
            }
        }
    }
}
