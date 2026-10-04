import Foundation

/// Remembers which sessions have already been reported as "needs you", and returns, per update,
/// the newly reported ones and the dropped ones. On the first call everything counts as already
/// reported (no flood right after app start).
public struct AttentionTracker {
    public struct Need: Equatable, Sendable {
        public let reason: String
        /// how long the session must hold rank 0 uninterrupted before it gets reported
        public let confirmAfter: TimeInterval

        public init(reason: String, confirmAfter: TimeInterval = 0) {
            self.reason = reason
            self.confirmAfter = confirmAfter
        }
    }

    /// since when a session has held rank 0 uninterrupted
    private var since: [String: Date] = [:]
    private var reported: Set<String> = []
    private var started = false

    public init() {}

    public mutating func update(_ needs: [String: Need], now: Date) -> (added: [String: String], removed: Set<String>) {
        since = since.filter { needs[$0.key] != nil }
        for name in needs.keys where since[name] == nil { since[name] = now }
        let removed = reported.subtracting(needs.keys)
        reported.subtract(removed)
        guard started else {
            started = true
            reported = Set(needs.keys)
            return ([:], [])
        }
        var added: [String: String] = [:]
        for (name, need) in needs where !reported.contains(name) {
            guard let first = since[name], now.timeIntervalSince(first) >= need.confirmAfter else { continue }
            added[name] = need.reason
            reported.insert(name)
        }
        return (added, removed)
    }
}
