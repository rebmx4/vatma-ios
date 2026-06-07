import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Latest APNs device token (hex). Stored so the web layer can register it
    /// once the user is authenticated (the JWT lives in the WKWebView).
    static var apnsTokenHex: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Запрос разрешения на пуши + регистрация в APNs. Вызывается из ViewController
    /// после первой загрузки контента (а не на холодном старте — рекомендация Apple HIG).
    func registerForPush() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        AppDelegate.apnsTokenHex = token
        // Register via the WKWebView so the POST carries the app's Bearer JWT.
        // A bare URLSession request would be unauthenticated (the JWT is held in
        // the web layer's localStorage, not in shared cookies) and rejected 401.
        DispatchQueue.main.async {
            ViewController.shared?.registerApnsTokenInWeb(token)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .badge, .sound])
    }

    /// Notification tapped: clear the app-icon badge and jump to chats.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        UIApplication.shared.applicationIconBadgeNumber = 0
        let info = response.notification.request.content.userInfo
        if let event = info["event"] as? String, event == "message" {
            DispatchQueue.main.async { ViewController.shared?.openChats() }
        }
        completionHandler()
    }
}
