import Foundation
import CoreLocation
import Observation
import Network

@MainActor
@Observable
final class AppState {
    // Auth
    var user: BoxUser?           = nil
    var pendingScreen: String?   = nil

    // Map data
    var businesses: [Business]   = []
    var popups: [FraisePopup]    = []
    var varieties: [Variety]     = []

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
    var userLocation: CLLocationCoordinate2D? = nil

    // Social
    var socialAccess: UserSocialAccess? = nil

    // Re-auth
    var needsReauth: Bool = false

    // Sheet detent requests — ContentView observes and applies
    var requestedDetent: Double? = nil

    // Popups the user has joined this session
    var joinedPopupIds: Set<Int> = []

    // Network
    var isOffline: Bool = false
    private var networkMonitor: NWPathMonitor?

    // Computed
    var isSignedIn: Bool { user != nil }
    var approvedBusinesses: [Business] { businesses.filter { $0.isApproved && $0.coordinate != nil } }
    var unapprovedBusinesses: [Business] { businesses.filter { !$0.isApproved && $0.coordinate != nil } }

    var nearestCollection: Business? {
        guard let userLoc = userLocation else {
            return approvedBusinesses.first(where: { $0.isCollection })
        }
        return approvedBusinesses
            .filter { $0.isCollection }
            .min(by: { a, b in
                let dA = CLLocation(latitude: a.lat!, longitude: a.lng!).distance(from: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude))
                let dB = CLLocation(latitude: b.lat!, longitude: b.lng!).distance(from: CLLocation(latitude: userLoc.latitude, longitude: userLoc.longitude))
                return dA < dB
            })
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

        if let b = await biz  { businesses = b }
        if let p = await pops { popups = p }
        if let v = await vars { varieties = v.filter { $0.active ?? true } }

        guard let token = Keychain.userToken else { return }
        if let me = try? await APIClient.shared.fetchMe(token: token) {
            user = me
            persist(user: me)
        }
    }

    // MARK: - Auth

    func signIn(response: AuthResponse) async {
        Keychain.userToken = response.token
        let me = BoxUser(id: response.userId, displayName: response.displayName, verified: response.verified)
        user = me
        persist(user: me)
        panel = .home
        if let pt = pushToken {
            try? await APIClient.shared.updatePushToken(pt, token: response.token)
        }
        await AppAttest.shared.ensureAttestation(userToken: response.token)
    }

    func signOut() {
        Keychain.userToken = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.userCacheKey)
        panel = .home
    }

    /// Call when any API call returns 401 — clears session and prompts re-auth.
    func handleUnauthorized() {
        signOut()
        needsReauth = true
        panel = .auth
    }

    func refresh() async {
        async let biz  = try? await APIClient.shared.fetchBusinesses()
        async let pops = try? await APIClient.shared.fetchPopups()
        if let b = await biz  { businesses = b }
        if let p = await pops { popups = p }
        writeWidgetData()
    }

    // Write shared data for the home screen widget via App Group
    func writeWidgetData() {
        guard let nearest = nearestCollection,
              let defaults = UserDefaults(suiteName: "group.com.boxfraise.app") else { return }
        defaults.set(nearest.name, forKey: "widget_location_name")
        defaults.set(nearest.displayCity, forKey: "widget_location_city")
        defaults.set(popups.filter { $0.isOpen }.count, forKey: "widget_popup_count")
    }

    /// Central API error handler — call from any panel catch block.
    func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            handleUnauthorized()
        }
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

    /// Called when the app backgrounds — clears payment/order state from memory.
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
