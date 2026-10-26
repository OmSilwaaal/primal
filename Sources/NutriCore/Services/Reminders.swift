import Foundation
import UserNotifications

/// Opt-in local reminders in the brand voice. Nothing is scheduled, and permission isn't requested, until the
/// person turns a reminder on in Settings. No marketing notifications.
enum Reminders {
    enum Kind: String, CaseIterable {
        case eveningLog, morningSun

        var settingsKey: String { "reminder.\(rawValue)" }
        var hour: Int { self == .eveningLog ? 20 : 8 }
        var title: String { self == .eveningLog ? "ᛉ Vitalis" : "ᛉ Morning light" }
        var body: String {
            self == .eveningLog
                ? "Log today's meals and water before you wind down."
                : "Ten minutes outside early helps set your body clock."
        }
    }

    static func isOn(_ kind: Kind) -> Bool { UserDefaults.standard.bool(forKey: kind.settingsKey) }

    /// Turns a reminder on (asking for permission the first time) or off. Returns false if permission was denied.
    @discardableResult
    static func set(_ kind: Kind, on: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard on else {
            center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
            UserDefaults.standard.set(false, forKey: kind.settingsKey)
            return true
        }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            UserDefaults.standard.set(false, forKey: kind.settingsKey)
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: kind.hour, minute: 0), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: trigger))
        UserDefaults.standard.set(true, forKey: kind.settingsKey)
        return true
    }
}
