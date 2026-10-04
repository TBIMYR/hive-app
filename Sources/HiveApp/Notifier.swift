import AppKit
import HiveCore
import UserNotifications

/// macOS notifications and dock badge for sessions with rank 0 ("needs you").
/// Without an app bundle (swift run) there is no bundle identifier; then only the dock badge,
/// because UNUserNotificationCenter.current() throws an exception without an identifier.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Click on a notification: session name
    var onSelect: ((String) -> Void)?

    private var tracker = AttentionTracker()
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
    }

    /// Call early (applicationWillFinishLaunching), otherwise a click that first launches the app gets lost.
    func start() {
        guard let center else { return }
        center.delegate = self
        // The tracker no longer knows about notifications from the previous run; the dock badge is correct immediately anyway
        center.removeAllDeliveredNotifications()
        // .badge is needed: with a bundle identifier, macOS only shows the dock badge if "Badges" is allowed
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// After every refresh: set the dock badge, report new sessions, remove resolved notifications.
    func update(_ needs: [String: AttentionTracker.Need], selected: String?, now: Date = Date()) {
        NSApp.dockTile.badgeLabel = needs.isEmpty ? nil : String(needs.count)
        let (added, removed) = tracker.update(needs, now: now)
        guard let center else { return }
        if !removed.isEmpty { center.removeDeliveredNotifications(withIdentifiers: Array(removed)) }
        for (name, reason) in added.sorted(by: { $0.key < $1.key }) {
            // whoever is already looking at the session doesn't need a notification
            if NSApp.isActive && selected == name { continue }
            let content = UNMutableNotificationContent()
            content.title = name
            content.body = reason
            content.sound = .default
            center.add(UNNotificationRequest(identifier: name, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let name = response.notification.request.identifier
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            self.onSelect?(name)
            completionHandler()
        }
    }
}
