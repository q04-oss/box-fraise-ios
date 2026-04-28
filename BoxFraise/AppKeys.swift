import Foundation

// MARK: - AppStorage keys

/// All @AppStorage and UserDefaults.standard keys in one place.
/// Using typed constants prevents typos and makes key inventory auditable.
enum AppStorageKey {
    static let akènePrevRank     = "akene_prev_rank"
    static let openToDates       = "open_to_dates"
    static let disappearDays     = "thread_disappear_days"
    static let recentSearches    = "recentSearches"
}

// MARK: - Keychain keys

enum KeychainKey {
    static let userToken         = "box_fraise_token"
    static let attestKeyID       = "fraise_attest_key_id"
    static let attestDone        = "fraise_attest_done"
    // Messaging session keys follow the pattern "session_<userId>"
    static func session(for userId: Int) -> String { "session_\(userId)" }
}

// MARK: - Push notification payload keys

enum NotificationPayloadKey {
    static let screen   = "screen"
    static let orderId  = "order_id"
    static let status   = "status"
}

// MARK: - App Group keys (widget data)

enum AppGroupKey {
    static let suiteName     = "group.com.boxfraise.app"
    static let locationName  = "widget_location_name"
    static let locationCity  = "widget_location_city"
    static let popupCount    = "widget_popup_count"
}

// MARK: - Deep link paths

/// Exhaustive set of in-app routing paths.
/// `AppState.route(to:)` maps these strings to Panel cases.
enum DeepLinkPath: String {
    case orderHistory  = "order-history"
    case popups        = "popups"
    case profile       = "profile"
    case verify        = "verify"
    case standingOrders = "standingOrders"
    case inbox         = "inbox"
    case messages      = "messages"
    case referrals     = "referrals"
    case meet          = "meet"
    case akene         = "akene"
    case offers        = "offers"
    case memory        = "memory"
}

// MARK: - Shared UserDefaults keys (non-AppStorage)

enum UserDefaultsKey {
    static let cachedUser = "cached_box_user"
}
