import AppKit
import HiveCore
import UserNotifications

/// macOS-Mitteilungen und Dock-Zahl für Sessions mit Rang 0 („braucht dich“).
/// Ohne App-Paket (swift run) gibt es keine Bundle-Kennung; dann nur die Dock-Zahl,
/// denn UNUserNotificationCenter.current() wirft ohne Kennung eine Ausnahme.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Klick auf eine Mitteilung: Session-Name
    var onSelect: ((String) -> Void)?

    private var tracker = AttentionTracker()
    private let center: UNUserNotificationCenter?

    override init() {
        center = Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
        super.init()
    }

    /// Früh aufrufen (applicationWillFinishLaunching), sonst geht ein Klick verloren, der die App erst startet.
    func start() {
        guard let center else { return }
        center.delegate = self
        // Mitteilungen aus dem vorigen Lauf kennt der Tracker nicht mehr; die Dock-Zahl stimmt ohnehin sofort
        center.removeAllDeliveredNotifications()
        // .badge ist nötig: mit Bundle-Kennung zeigt macOS die Dock-Zahl nur, wenn „Kennzeichen“ erlaubt ist
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Nach jeder Aktualisierung: Dock-Zahl setzen, neue Sessions melden, erledigte Mitteilungen entfernen.
    func update(_ needs: [String: AttentionTracker.Need], selected: String?, now: Date = Date()) {
        NSApp.dockTile.badgeLabel = needs.isEmpty ? nil : String(needs.count)
        let (added, removed) = tracker.update(needs, now: now)
        guard let center else { return }
        if !removed.isEmpty { center.removeDeliveredNotifications(withIdentifiers: Array(removed)) }
        for (name, reason) in added.sorted(by: { $0.key < $1.key }) {
            // wer die Session gerade vor sich hat, braucht keine Mitteilung
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
