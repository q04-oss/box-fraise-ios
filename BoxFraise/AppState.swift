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
    var businesses: [Business]  = [] { didSet { invalidateBusinessCaches() } }
    var popups: [FraisePopup]   = []
    var varieties: [Variety]    = []
    private var _approvedCache:   [Business]?
    private var _unapprovedCache: [Business]?

    // Navigation
    private(set) var panel: Panel = .home

    // All panel changes flow through this single method — panel is private(set).
    @MainActor func navigate(to destination: Panel) { panel = destination }
    var activeLocation: Business? = nil

    // Ordering
    var orderState: OrderState   = OrderState()
    var confirmedOrder: ConfirmedOrder? = nil

    // Order history
    var orderHistory: [PastOrder] = []

    // Staff
    var staffAccessCode: String          = ""
    var pendingStaffOrders: [StaffOrder] = []

    // Walk-in
    var walkInInventory: [WalkInItem] = []

    // User location
    var userLocation: CLLocationCoordinate2D? = nil {
        didSet { invalidateBusinessCaches() }
    }

    // Social
    var socialAccess: UserSocialAccess? = nil

    // Messaging
    var totalUnreadMessages: Int = 0

    // Set by handleUnauthorized(); cleared by the re-auth banner dismiss button.
    var needsReauth: Bool = false

    // Set when key publication fails after all retries; shown as a dismissible banner.
    // Non-fatal — the user can still receive messages from existing sessions.
    var messagingKeysPublishFailed: Bool = false

    // Set to the target fraction; ContentView applies it and resets to nil to prevent re-triggering.
    var requestedDetent: Double? = nil

    // Set by AppDelegate on notification tap; consumed once by ContentView's onChange.
    var pendingScreen: String? = nil

    // Session-only — not persisted. Prevents duplicate join requests while a Stripe payment sheet
    // is in flight. Server is the source of truth; this is an optimistic local guard.
    var joinedPopupIds: Set<Int> = []

    // Network
    var isOffline: Bool = false
    private var networkMonitor: NWPathMonitor?

    // User preferences — backed by UserDefaults, not @AppStorage, so views
    // don't own persistence state.
    // Not @Observable — views reading these won't auto-update on external UserDefaults changes.
    // Reads are always current; observation is manual.
    var openToDates: Bool {
        get { UserDefaults.standard.bool(forKey: AppStorageKey.openToDates) }
        set { UserDefaults.standard.set(newValue, forKey: AppStorageKey.openToDates) }
    }

    // Previous akène rank — used to compute the rank-delta arrow in AkenePanel.
    // Stored in UserDefaults so it survives session boundaries.
    var prevAkeneRank: Int {
        get { UserDefaults.standard.integer(forKey: AppStorageKey.akènePrevRank) }
        set { UserDefaults.standard.set(newValue, forKey: AppStorageKey.akènePrevRank) }
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
    // The most recent paid or ready order — shown as the active pickup in the home sheet.
    var activeOrder: PastOrder? { orderHistory.first { $0.isPaid } }

    // Cached nearest collection — recomputed only when businesses or userLocation changes.
    // Location unknown — fall back to first collection in list (server returns nearest-first by default).
    private var _nearestCollectionCache: Business?
    var nearestCollection: Business? {
        if let cached = _nearestCollectionCache { return cached }
        let result: Business?
        if let userLoc = userLocation {
            result = approvedBusinesses
                .filter { $0.isCollection }
                .min { a, b in
                    guard let latA = a.lat, let lngA = a.lng,
                          let latB = b.lat, let lngB = b.lng else { return false }
                    let locA = CLLocation(latitude: latA, longitude: lngA)
                    let locB = CLLocation(latitude: latB, longitude: lngB)
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
    private static let userCacheKey = UserDefaultsKey.cachedUser

    // MARK: - Network monitor

    func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        networkMonitor = monitor
        // Weak capture prevents the monitor callback from holding AppState alive after the scene is destroyed.
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    // MARK: - Bootstrap — called once at app launch, not on scene resume

    func bootstrap() async {
        restoreCachedUser()
        await refreshPublicMapData()
        guard let token = Keychain.userToken else { return }
        await loadUserData(token: token)
        publishMessagingKeys(token: token)
    }

    // Phase 1: Populate UI immediately from on-disk cache before any network call.
    private func restoreCachedUser() {
        loadCache()
    }

    // Phase 2: Public data — businesses, popups, varieties. No auth required.
    private func refreshPublicMapData() async {
        async let biz  = try? await APIClient.shared.fetchBusinesses()
        async let pops = try? await APIClient.shared.fetchPopups()
        async let vars = try? await APIClient.shared.fetchVarieties()
        if let b = await biz  { businesses = b; invalidateBusinessCaches() }
        if let p = await pops { popups = p }
        // Server omits 'active' on legacy variety records — treat absence as active.
        if let v = await vars { varieties = v.filter { $0.isActive } }
    }

    // Phase 3: User-specific data — requires a valid session token.
    private func loadUserData(token: FraiseToken) async {
        async let me   = try? await APIClient.shared.fetchMe(token: token)
        async let hist = try? await APIClient.shared.fetchOrderHistory(token: token)
        if let u = await me   { user = u; persist(user: u) }
        if let h = await hist { orderHistory = h }
    }

    // Phase 4: Publish public Signal keys to the key server in the background.
    // On failure after retries, sets messagingKeysPublishFailed so the UI can
    // inform the user — new contacts cannot establish sessions until keys are published.
    private func publishMessagingKeys(token: FraiseToken) {
        Task {
            do {
                try await FraiseMessaging.shared.publishPublicKeys(token: token)
            } catch {
                messagingKeysPublishFailed = true
            }
        }
    }

    // MARK: - Auth

    func signIn(response: AuthResponse) async {
        // Guard against double sign-in from rapid taps — second call is a no-op.
        guard user == nil else { return }
        // Fresh check bypasses the cached result — a hook that returns false on first call
        // cannot protect a subsequent sign-in from detection.
        guard !AppSecurity.isJailbrokenFresh() else { return }
        Keychain.userToken = response.token
        let me = BoxUser(id: response.userId, displayName: response.displayName,
                         verified: response.verified ?? false, isShop: false,
                         fraiseChatEmail: nil, currentStreakWeeks: nil, socialTier: nil, status: nil)
        user = me
        persist(user: me)
        navigate(to: .home)
        if let pt = pushToken {
            try? await APIClient.shared.updatePushToken(pt, token: response.token)
        }
        await AppAttest.shared.ensureAttestation(userToken: response.token)
        Task { try? await FraiseMessaging.shared.publishPublicKeys(token: response.token) }
    }

    func signOut() {
        Keychain.userToken = nil
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.userCacheKey)
        navigate(to: .home)
    }

    func handleUnauthorized() {
        signOut()
        needsReauth = true
        navigate(to: .auth)
    }

    func refreshMapData() async {
        async let biz  = try? await APIClient.shared.fetchBusinesses()
        async let pops = try? await APIClient.shared.fetchPopups()
        if let b = await biz  { businesses = b; invalidateBusinessCaches() }
        if let p = await pops { popups = p }
        updateHomeScreenWidget()
    }

    // MARK: - Deep link routing

    // Centralises the string → Panel mapping so ContentView and AppDelegate
    // don't need to know the routing logic.
    func route(to screenName: String) {
        let destination: Panel
        switch screenName {
        case DeepLinkPath.orderHistory.rawValue:   destination = .orderHistory
        case DeepLinkPath.popups.rawValue:          destination = .popups
        case DeepLinkPath.profile.rawValue:         destination = isSignedIn ? .profile : .auth
        case DeepLinkPath.verify.rawValue:          destination = .nfcVerify
        case DeepLinkPath.standingOrders.rawValue:  destination = isSignedIn ? .standingOrders : .auth
        case DeepLinkPath.inbox.rawValue,
             DeepLinkPath.messages.rawValue:         destination = isSignedIn ? .messages : .auth
        case DeepLinkPath.referrals.rawValue:       destination = isSignedIn ? .referrals : .auth
        case DeepLinkPath.meet.rawValue:            destination = isSignedIn ? .meet : .auth
        case DeepLinkPath.akene.rawValue:           destination = isSignedIn ? .akene : .auth
        case DeepLinkPath.offers.rawValue,
             DeepLinkPath.memory.rawValue:           destination = isSignedIn ? .messages : .auth
        default:                                    destination = .home
        }
        navigate(to: destination)
        requestedDetent = 0.55
    }

    // Write shared data for the home screen widget via App Group
    func updateHomeScreenWidget() {
        guard let nearest = nearestCollection,
              let defaults = UserDefaults(suiteName: AppGroupKey.suiteName) else { return }
        defaults.set(nearest.name, forKey: AppGroupKey.locationName)
        defaults.set(nearest.displayCity ?? "", forKey: AppGroupKey.locationCity)
        defaults.set(popups.filter { $0.isOpen }.count, forKey: AppGroupKey.popupCount)
    }

    func routeAPIError(_ error: Error) {
        if case APIError.unauthorized = error { handleUnauthorized() }
    }

    // MARK: - Cache invalidation

    private func invalidateBusinessCaches() {
        _approvedCache = nil
        _unapprovedCache = nil
        _nearestCollectionCache = nil
    }

    func selectLocation(_ biz: Business) {
        guard biz.isApproved else { return }
        activeLocation = biz
        orderState.reset()
        confirmedOrder = nil
        navigate(to: biz.isCollection ? .order : .home)
        requestedDetent = 0.5
        Task { await loadVarieties() }
    }

    func clearLocation() {
        activeLocation = nil
        orderState.reset()
        confirmedOrder = nil
        navigate(to: .home)
    }

    func clearSensitiveState() {
        orderState.reset()
        confirmedOrder = nil
        staffAccessCode = ""
        pendingStaffOrders = []
    }

    func loadVarieties() async {
        if let v = try? await APIClient.shared.fetchVarieties() {
            varieties = v.filter { $0.isActive }
        }
    }

    func refreshUser() async {
        guard let token = Keychain.userToken else { return }
        do {
            async let me     = try await APIClient.shared.fetchMe(token: token)
            async let social = try? await APIClient.shared.fetchSocialAccess(token: token)
            let u = try await me
            user = u; persist(user: u)
            if let s = await social { socialAccess = s }
        } catch {
            routeAPIError(error)
        }
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
