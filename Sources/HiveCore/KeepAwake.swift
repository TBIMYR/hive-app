import Foundation

/// Rule for keeping the Mac awake (like Amphetamine): off, while at least one session is working (also in
/// the background; waiting for you or ready doesn't count), or always, without a limit.
public enum KeepAwake {
    public enum Mode: String, CaseIterable, Sendable {
        case off, whileWorking, always

        /// Order of the title bar switch: while working → always → off → while working
        public var next: Mode {
            switch self {
            case .whileWorking: .always
            case .always: .off
            case .off: .whileWorking
            }
        }
    }

    public static func working(_ statuses: [SessionStatus]) -> Int {
        statuses.filter { $0.cls == "busy" }.count
    }

    /// Reason for the power assertion (shows in `pmset -g assertions`), nil = let the Mac sleep.
    public static func reason(mode: Mode, statuses: [SessionStatus]) -> String? {
        if mode == .always { return "Hive: keep awake" }
        let n = working(statuses)
        guard mode == .whileWorking, n > 0 else { return nil }
        return n == 1 ? "Hive: 1 session is working" : "Hive: \(n) sessions are working"
    }
}
