import Foundation
import UserNotifications
import IslandCore

/// Wraps UNUserNotificationCenter. Requires the app to run from a bundle with a
/// CFBundleIdentifier (see Scripts/bundle.sh) — otherwise authorization is denied.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Called with the sessionId attached to a notification the user clicked.
    var onClick: (@Sendable (String) -> Void)?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ request: NotificationRequest) {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        // No system chime: the island plays its own 8-bit synth blip per event
        // (see SoundSynthesizer, wired in AppModel.handle).
        content.sound = nil
        content.userInfo = ["sessionId": request.sessionId]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // Show banners even when the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    // Handle clicks.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let sid = response.notification.request.content.userInfo["sessionId"] as? String {
            let callback = onClick
            Task { @MainActor in callback?(sid) }
        }
        completionHandler()
    }
}
