import UserNotifications

/// Posts a system notification when the iPad connects or disconnects while MirrorScreen is in the background.
final class ConnectionNotifier {
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                Log.ui.error("Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                Log.ui.info("Notifications not allowed")
            }
        }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
