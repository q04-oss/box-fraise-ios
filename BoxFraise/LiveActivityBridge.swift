import ActivityKit

// MARK: - Live Activity bridge for the main app target
// BoxFraiseOrderAttributes is also defined in Extensions/LiveActivity.swift
// for the Widget Extension target. When adding the widget extension in Xcode,
// keep this file in the main target and LiveActivity.swift in the extension target only.

@available(iOS 16.2, *)
struct BoxFraiseOrderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var statusLabel: String
    }
    public let orderId: Int
    public let varietyName: String
    public let locationName: String
}

@available(iOS 16.2, *)
func startOrderLiveActivity(orderId: Int, varietyName: String, locationName: String) {
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
func updateOrderLiveActivity(orderId: Int, status: String) {
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
