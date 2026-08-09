import Foundation
import UserNotifications

/// Local notifications — the "an agent reached your desk" signal.
///
/// By default macOS does not present banners while the app is frontmost,
/// which is exactly the behavior we want: the room itself is the signal
/// when you're looking at it; the banner exists for when you're not.
/// No delegate needed for that — it's the system default.
enum Notifier {

    /// Asks once; macOS remembers the answer. Called at launch so the
    /// permission prompt appears before the first agent ever arrives.
    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// "circle — Finished, waiting at your desk."
    static func agentArrived(project: String) {
        let content = UNMutableNotificationContent()
        content.title = project
        content.body = String(localized: "Finished — waiting at your desk.")

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // now
        )
        UNUserNotificationCenter.current().add(request)
    }
}
