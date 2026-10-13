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
    private var phone = PhonePush()
    /// The Mac is about to sleep (Sleep When Done): counts as away for the phone push
    var leaving = false
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
        if Self.phoneOn, let topic = Self.phoneTopic {
            let away = leaving || Self.idleSeconds >= Double(Self.awayMinutes) * 60
            for (name, reason) in phone.update(added: added, removed: removed, away: away) {
                Self.sendToPhone(topic: topic, title: name, body: reason)
            }
        }
        guard let center else { return }
        if !removed.isEmpty { center.removeDeliveredNotifications(withIdentifiers: Array(removed)) }
        for (name, reason) in added.sorted(by: { $0.key < $1.key }) {
            // whoever is already looking at the session doesn't need a notification
            if NSApp.isActive && selected == name { continue }
            let content = UNMutableNotificationContent()
            content.title = name
            content.body = reason
            content.sound = Self.soundOn ? .default : nil
            center.add(UNNotificationRequest(identifier: name, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.soundOn ? [.banner, .sound] : [.banner])
    }

    /// Settings switch "Ping when a session needs you", stored under `notifySound` (default on)
    nonisolated static let soundKey = "notifySound"
    nonisolated static var soundOn: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }

    // MARK: Phone (ntfy)

    /// Settings: push "needs you" to the phone via ntfy.sh while Mika is away (no mouse/keyboard input for
    /// `awayMinutes`). The topic is a random secret; the ntfy app on the phone subscribes to it.
    nonisolated static let phoneKey = "phonePush"
    nonisolated static let topicKey = "ntfyTopic"
    nonisolated static let awayKey = "phoneAwayMinutes"
    static var phoneOn: Bool { UserDefaults.standard.bool(forKey: phoneKey) }
    static var awayMinutes: Int { UserDefaults.standard.object(forKey: awayKey) as? Int ?? 5 }
    static var phoneTopic: String? {
        UserDefaults.standard.string(forKey: topicKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A topic nobody guesses: "hive-" plus 20 random letters and digits.
    static func newTopic() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "hive-" + String((0..<20).map { _ in chars.randomElement()! })
    }

    /// Seconds since the last mouse or keyboard input on this Mac.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static func sendToPhone(topic: String, title: String, body: String) {
        guard let url = URL(string: "https://ntfy.sh/\(topic)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        // ntfy reads non-ASCII header values only RFC 2047-encoded; session names are ASCII anyway
        req.setValue(title, forHTTPHeaderField: "Title")
        req.setValue("high", forHTTPHeaderField: "Priority")
        req.setValue("bell", forHTTPHeaderField: "Tags")
        URLSession.shared.dataTask(with: req).resume()
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
