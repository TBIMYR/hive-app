import Foundation

/// Merkt sich, welche Sessions schon als „braucht dich“ gemeldet wurden, und liefert je Aktualisierung
/// die neu zu meldenden und die weggefallenen. Beim ersten Aufruf gilt alles als schon gemeldet
/// (keine Flut nach dem App-Start).
public struct AttentionTracker {
    public struct Need: Equatable, Sendable {
        public let reason: String
        /// so lange muss die Session ununterbrochen Rang 0 haben, bevor sie gemeldet wird
        public let confirmAfter: TimeInterval

        public init(reason: String, confirmAfter: TimeInterval = 0) {
            self.reason = reason
            self.confirmAfter = confirmAfter
        }
    }

    /// seit wann eine Session ununterbrochen Rang 0 hat
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
