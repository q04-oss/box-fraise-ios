import SwiftUI
import UserNotifications
import StripePaymentSheet
import os.log

@main
struct BoxFraiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var screenshotTaken = false
    @State private var isScreenCaptured = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .fraiseTheme()
                // Screenshot telemetry — blur fires after capture, not before (cosmetic only)
                .blur(radius: screenshotTaken ? 20 : 0)
                .animation(.easeInOut(duration: 0.2), value: screenshotTaken)
                // Background snapshot privacy — covers app switcher screenshot
                .overlay {
                    if scenePhase == .background || isScreenCaptured {
                        Color(.systemBackground)
                            .ignoresSafeArea()
                            .overlay {
                                Image(systemName: "strawberry")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.quaternary)
                            }
                    }
                }
                // Re-auth banner
                .overlay(alignment: .top) {
                    if appState.needsReauth {
                        ReauthBanner { appState.needsReauth = false }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                // Offline banner
                .overlay(alignment: .top) {
                    if appState.isOffline {
                        OfflineBanner()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                // Key publication failure banner
                .overlay(alignment: .top) {
                    if appState.messagingKeysPublishFailed {
                        KeysFailedBanner { appState.messagingKeysPublishFailed = false }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onAppear {
                    appDelegate.appState = appState
                    AppSecurity.enforce()
                    appState.startNetworkMonitor()
                    isScreenCaptured = Self.isScreenBeingRecorded
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIScreen.capturedDidChangeNotification)
                ) { _ in
                    isScreenCaptured = Self.isScreenBeingRecorded
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        appState.clearSensitiveState()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                    screenshotTaken = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        screenshotTaken = false
                    }
                }
                .task { await appState.bootstrap() }
        }
    }
}

// MARK: - Screen capture helper

extension BoxFraiseApp {
    // UIScreen.main is deprecated in iOS 16. Prefer the scene-based accessor;
    // fall back to UIScreen.main only when no window scene is available.
    static var isScreenBeingRecorded: Bool {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen ?? UIScreen.main)
            .isCaptured
    }
}

// MARK: - Deep link handler (extension on BoxFraiseApp)

extension BoxFraiseApp {
    @MainActor func handleDeepLink(_ url: URL) {
        let path = url.path.lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems

        switch path {
        case "/order":
            if let slug = query?.first(where: { $0.name == "location" })?.value,
               let biz = appState.approvedBusinesses.first(where: { $0.slug == slug }) {
                appState.selectLocation(biz)
            } else {
                appState.navigate(to: .order)
            }
        case "/popups", "/popup":
            appState.navigate(to: .popups)
        case "/profile":
            appState.navigate(to: appState.isSignedIn ? .profile : .auth)
        case "/verify":
            appState.navigate(to: .nfcVerify)
        case "/history":
            appState.navigate(to: appState.isSignedIn ? .orderHistory : .auth)
        case "/standing-orders":
            appState.navigate(to: appState.isSignedIn ? .standingOrders : .auth)
        case "/inbox", "/messages":
            appState.navigate(to: appState.isSignedIn ? .messages : .auth)
        case "/referrals":
            appState.navigate(to: appState.isSignedIn ? .referrals : .auth)
        case "/meet":
            appState.navigate(to: appState.isSignedIn ? .meet : .auth)
        default:
            break
        }
    }
}

// MARK: - Offline banner

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11))
                .foregroundStyle(.white)
            Text("no connection — some features unavailable")
                .font(.mono(11))
                .foregroundStyle(.white)
                .tracking(0.2)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color(.black))
        .fraiseTheme()
    }
}

// MARK: - Re-auth banner

struct ReauthBanner: View {
    @Environment(\.fraiseColors) private var c
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Text("session expired — please sign in again")
                .font(.mono(11))
                .foregroundStyle(c.background)
                .tracking(0.3)
            Spacer()
            Button(action: onDismiss) {
                Text("×").font(.mono(14)).foregroundStyle(c.background)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color.fraiseRed)
        .fraiseTheme()
    }
}

// MARK: - Key publication failure banner

struct KeysFailedBanner: View {
    @Environment(\.fraiseColors) private var c
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(c.background)
            Text("encryption keys unavailable — new contacts can't message you")
                .font(.mono(11))
                .foregroundStyle(c.background)
                .tracking(0.2)
            Spacer()
            Button(action: onDismiss) {
                Text("×").font(.mono(14)).foregroundStyle(c.background)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(Color.fraiseOrange)
        .fraiseTheme()
    }
}

// MARK: - Previews

#Preview("Offline banner") {
    OfflineBanner().fraiseTheme()
}

#Preview("Reauth banner") {
    ReauthBanner {}.fraiseTheme()
}

#Preview("Keys failed banner") {
    KeysFailedBanner {}.fraiseTheme()
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Weak to avoid a retain cycle; BoxFraiseApp's @State owns the instance.
    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Config.validate()
        UNUserNotificationCenter.current().delegate = self
        STPAPIClient.shared.publishableKey = Config.stripePublishableKey
        requestPushPermission(application)
        return true
    }

    private func requestPushPermission(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in application.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await appState?.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal — order-ready notifications will not arrive, but the app functions normally.
        os_log(.info, "Push registration failed: %@", error.localizedDescription)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let screen = response.notification.request.content.userInfo["screen"] as? String
        Task { @MainActor in
            guard self.appState != nil else {
                os_log(.error, "AppDelegate: appState is nil — deep-link navigation lost for screen '%@'", screen ?? "nil")
                return
            }
            self.appState?.pendingScreen = screen
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let orderId = (info["order_id"] as? Int) ?? Int(info["order_id"] as? String ?? "")
        let status  = info["status"] as? String
        if let orderId, let status {
            Task { @MainActor in
                if #available(iOS 16.2, *) {
                    updateOrderLiveActivity(orderId: orderId, status: status)
                }
                await appState?.refreshMapData()
            }
        }
        completionHandler([.banner, .sound, .badge])
    }
}
