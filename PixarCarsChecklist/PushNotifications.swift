import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
import UserNotifications

enum MEPushNotificationCenter {
    static let didReceiveDeviceToken = Notification.Name("MEPushNotificationCenter.didReceiveDeviceToken")
    static let tokenUserInfoKey = "token"

    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func requestAuthorizationAndRegister() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    static func tokenString(from deviceToken: Data) -> String {
        deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    }
}

final class MEPushNotificationAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = MEPushNotificationCenter.tokenString(from: deviceToken)
        UserDefaults.standard.set(token, forKey: "socialPushDeviceToken")
        NotificationCenter.default.post(
            name: MEPushNotificationCenter.didReceiveDeviceToken,
            object: nil,
            userInfo: [MEPushNotificationCenter.tokenUserInfoKey: token]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Remote notification registration failed: \(error.localizedDescription)")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
#endif
