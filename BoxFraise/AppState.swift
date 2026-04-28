import Foundation
import CoreLocation
import Observation
import Network

@MainActor
@Observable
final class AppState {
    // Auth
    var user: BoxUser? = nil

    // Map data
    var businesses: [Business]  = [] { didSet { _approvedCache = nil; _unapprovedCache = nil } }
    var popups: [FraisePopup]   = []
    var varieties: [Variety]    = []
    private var _approvedCache:   [Business]?
    private var _unapprovedCache: [Business]?

    // Navigation
    var panel: Panel             = .home
    var activeLocation: Business? = nil

    // Ordering
    var orderState: OrderState   = OrderState()
    var confirmedOrder: ConfirmedOrder? = nil

    // Order history
    var orderHistory: [PastOrder] = []

    // Staff
    var staffPin: String          = ""
    var staffOrders: [StaffOrder] = []

    // Walk-in
    var walkInInventory: [WalkInItem] = []

    // User location
    var userLocation: CLLocationCoordinate2D? = nil {
        didSet { _nearestCollectionCache = nil }
    }

    // Social
    var socialAccess: UserSocialAccess? = nil

    // Messaging
    var totalUnreadMessages: Int = 0

    // Re-auth
    var needsReauth: Bool = false

    // Sheet detent requests — ContentView observes and applies
    var requestedDetent: Double? = nil

    // Popups the user has joined this session
    var joinedPopupIds: Set<Int> = []

    // Network
    var isOffline: Bool = false
    private var networkMonitor: NWPathMonitor?

    // User preferences — backed by UserDefaults, not @AppStorage, so views
    // don't own persistence state.
    var openToDates: Bool {
        get { UserDefaults.standard.bool(forKey: "open_to_dates") }
        set { UserDefaults.standard.set(newValue, forKey: "open_to_dates") }
    }

    // Previous akène rank — used to compute the rank-delta arrow in AkenePanel.
    // Stored in UserDefaults so it survives session boundaries.
    var prevAkeneRank: Int {
        get { UserDefaults.standard.integer(forKey: "akene_prev_rank") }
        set { UserDefaults.standard.set(newValue, forKey: "akene_prev_rank") }
    }

    // MARK: - Computed

    var isSignedIn: Bool { user != nil }
    var approvedBusinesses: [Business] {
        if let c = _approvedCache { return c }
        let r = businesses.filter { $0.isApproved && $0.coordinate != nil }
        _approvedCache = r; return r
    }
    var unapprovedBusinesses: [Business] {
        if let c = _unapprovedCache { return c }
        let r = businesses.filter { !$0.isApproved && $0.coordinate != nil }
        _unapprovedCache = r; return r
    }
    var activeOrder: PastOrder? { orderHistory.first { $0.isPaid } }

    // Cached nearest collection — recomputed only when businesses or userLocation changes.
    private var _nearestCollectionCache: Business?
    var nearestCollection: Business? {
        if let cached = _nearestCollectionCache { return cached }
        let result: Business?
        if let userLoc = userLocation {
            result = approvedBusinesses
                .filter { $0.isCollection }
                .min { a, b in
                    let locA = CLLocation(latitude: a.lat!, longitude: a.lng!)
                    let locB = CLLocation(latitude: b.lat!, longitude: b.lng!)
                    let ref  = CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude)
                    return locA.distance(from: ref) < locB.distance(from: ref)
                }
        } else {
            result = approvedBusinesses.first { $0.isCollection }
        }
        _nearestCollectionCache = result
        return result
    }

    // Cache keys
    private static let userCacheKey = "cached_box_user"

    // MARK: - Network monitor

    func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        loadCache()
        async let biz  = try? await APIClient.shared.fetchBusinesses()
        async let pops = try? await APIClient.shared.fetchPopups()
        async let vars = try? await APIClient.shared.fetchVarieties()

        if let b = await biz  { businesses = b; _nearestCollectionCache = nil }
        if let p = await pops { popups = p }
        if let v = await vars { varieties = v.filter { $0.active ?? true } }

        guard let token = Keychain.userToken else { return }
        async let me   = try? await APIClient.shared.fetchMe(token: token)
        async let hist = try? await APIClient.shared.fetchOrderHistory(token: token)
        if let u = await me   { user = u; persist(user: u) }
        if let h = await hist { orderHistory = h }
        Task { try? await FraiseMessaging.shared.publishKeys(token: token) }
    }

    // MARK: - Auth

    func signIn(response: AuthResponse) async {
        Keychain.userToken = response.token
        let me = BoxUser(id: response.userId, displayName: response.displayName,
                         verified: response.verified ?? false, isShop: false,
                         fraiseChatEmail: nil, currentStreakWeeks: nil, socialTier: nil, status: nil)
        user = me
        persist(user: me)
        panel = .home
        if let pt = pushToken {
            try? await APIClient.shared.updatePushToken(pt, token: response.token)
        }
        await AppAttest.shared.ensureAttestation(userToken: response.token)
        Task { try? await FraiseMessaging.shared.publishKeys(token: response.token) }
    }

    func signOut() {
        Keychain.userToken = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.userCacheKey)
        panel = .home
    }

    func handleUnauthorized() {
        signOut()
        needsReauth = true
        panel = .auth
    }

    func refresh() async {
        async let biz  = try? await APIClient.shared.fetchBusinesses()
        async let pops = try? await APIClient.shared.fetchPopups()
        if let b = await biz  { businesses = b; _nearestCollectionCache = nil }
        if let p = await pops { popups = p }
        writeWidgetData()
    }

    // MARK: - Deep link routing

    // Centralises the string → Panel mapping so ContentView and AppDelegate
    // don't need to know the routing logic.
    func route(to screenName: String) {
        switch screenName {
        case "order-history":  panel = .orderHistory
        case "popups":         panel = .popups
        case "profile":        panel = isSignedIn ? .profile : .auth
        case "verify":         panel = .nfcVerify
        case "standingOrders": panel = isSignedIn ? .standingOrders : .auth
        case "inbox",
             "messages":       panel = isSignedIn ? .messages : .auth
        case "referrals":      panel = isSignedIn ? .referrals : .auth
        case "meet":           panel = isSignedIn ? .meet : .auth
        case "akene":          panel = isSignedIn ? .akene : .auth
        case "offers",
             "memory":         panel = isSignedIn ? .messages : .auth
        default:               panel = .home
        }
        requestedDetent = 0.55
    }

    // Write shared data for the home screen widget via App Group
    func writeWidgetData() {
        guard let nearest = nearestCollection,
              let defaults = UserDefaults(suiteName: "group.com.boxfraise.app") else { return }
        defaults.set(nearest.name, forKey: "widget_location_name")
        defaults.set(nearest.displayCity, forKey: "widget_location_city")
        defaults.set(popups.filter { $0.isOpen }.count, forKey: "widget_popup_count")
    }

    func handle(_ error: Error) {
        if case APIError.unauthorized = error { handleUnauthorized() }
    }

    func selectLocation(_ biz: Business) {
        guard biz.isApproved else { return }
        activeLocation = biz
        orderState.reset()
        confirmedOrder = nil
        panel = biz.isCollection ? .order : .home
        requestedDetent = 0.5
        Task { await loadVarieties() }
    }

    func clearLocation() {
        activeLocation = nil
        orderState.reset()
        confirmedOrder = nil
        panel = .home
    }

    func clearSensitiveState() {
        orderState.reset()
        confirmedOrder = nil
        staffPin = ""
        staffOrders = []
    }

    func loadVarieties() async {
        if let v = try? await APIClient.shared.fetchVarieties() {
            varieties = v.filter { $0.active ?? true }
        }
    }

    func refreshUser() async {
        guard let token = Keychain.userToken else { return }
        async let me     = try? await APIClient.shared.fetchMe(token: token)
        async let social = try? await APIClient.shared.fetchSocialAccess(token: token)
        if let u = await me     { user = u; persist(user: u) }
        if let s = await social { socialAccess = s }
    }

    // MARK: - Push

    var pushToken: String?

    func registerPushToken(_ token: String) async {
        pushToken = token
        guard let sessionToken = Keychain.userToken else { return }
        try? await APIClient.shared.updatePushToken(token, token: sessionToken)
    }

    // MARK: - Cache

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: Self.userCacheKey),
           let u = try? JSONDecoder().decode(BoxUser.self, from: data) {
            user = u
        }
    }

    private func persist(user: BoxUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userCacheKey)
        }
    }
}
