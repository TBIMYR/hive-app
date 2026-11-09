import Foundation

/// Remembers which sessions have already been reported as "needs you", and returns, per update,
/// the newly reported ones and the dropped ones. On the first call everything counts as already
/// reported (no flood right after app start). A session that stops waiting and waits again with the same reason
/// within `flicker` (status jumping back and forth, the dialog redrawn) is not reported a second time.
public struct AttentionTracker {
    public static let flicker: TimeInterval = 30

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
    /// reported sessions that stopped waiting: their reason and when
    private var gone: [String: (reason: String, at: Date)] = [:]
    private var started = false
    private var lastReason: [String: String] = [:]

    public init() {}

    public mutating func update(_ needs: [String: Need], now: Date) -> (added: [String: String], removed: Set<String>) {
        since = since.filter { needs[$0.key] != nil }
        for name in needs.keys where since[name] == nil { since[name] = now }
        let removed = reported.subtracting(needs.keys)
        reported.subtract(removed)
        gone = gone.filter { now.timeIntervalSince($0.value.at) < Self.flicker }
        for name in removed { gone[name] = (lastReason[name] ?? "", now) }
        lastReason = needs.mapValues(\.reason)
        guard started else {
            started = true
            reported = Set(needs.keys)
            return ([:], [])
        }
        var added: [String: String] = [:]
        for (name, need) in needs where !reported.contains(name) {
            guard let first = since[name], now.timeIntervalSince(first) >= need.confirmAfter else { continue }
            if gone.removeValue(forKey: name)?.reason != need.reason { added[name] = need.reason }
            reported.insert(name)
        }
        return (added, removed)
    }
}
