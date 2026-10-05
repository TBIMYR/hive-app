import Foundation

/// Rule for keeping the Mac awake (like Amphetamine): only while the switch is on and at least one
/// session is working, also in the background. Waiting for you or ready doesn't count.
public enum KeepAwake {
    public static func working(_ statuses: [SessionStatus]) -> Int {
        statuses.filter { $0.cls == "busy" }.count
    }

    /// Reason for the power assertion (shows in `pmset -g assertions`), nil = let the Mac sleep.
    public static func reason(enabled: Bool, statuses: [SessionStatus]) -> String? {
        let n = working(statuses)
        guard enabled, n > 0 else { return nil }
        return n == 1 ? "Hive: 1 session is working" : "Hive: \(n) sessions are working"
    }
}
