import SwiftUI
import UserNotifications
import StripePaymentSheet

@main
struct BoxFraiseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var screenshotTaken = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .fraiseTheme()
                // Screenshot telemetry — blur fires after capture, not before (cosmetic only)
                .blur(radius: screenshotTaken ? 20 : 0)
                .animation(.easeInOut(duration: 0.2), value: screenshotTaken)
                // Re-auth banner
                .overlay(alignment: .top) {
                    if appState.needsReauth {
                        ReauthBanner { appState.needsReauth = false }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onAppear {
                    appDelegate.appState = appState
                    STPAPIClient.shared.publishableKey = Config.stripePublishableKey
                    // Run security checks
                    AppSecurity.enforce()
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
        .background(Color(hex: "C0392B"))
        .fraiseTheme()
    }
}

// MARK: - App config

enum Config {
    static let stripePublishableKey = "pk_test_51RcAlhKvPGIzTFOS9MjkghFT8B5Y2e4JSbEhP6DOV7EU1Pe47JS4X1Jslm6fukkyp8DYIgtJjJ5zLUZkbrnNBaJX00RINxJvdT"
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestPushPermission(application)
        return true
    }

    private func requestPushPermission(_ application: UIApplication) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await appState?.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let screen = response.notification.request.content.userInfo["screen"] as? String
        DispatchQueue.main.async { self.appState?.pendingScreen = screen }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
