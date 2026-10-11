import Foundation

/// Which "needs you" reports go to the phone: only while Mika is away from the Mac, each open need once,
/// including one that was already open when Mika left. Fed with the output of AttentionTracker.
public struct PhonePush {
    /// open needs (name → reason)
    private var open: [String: String] = [:]
    private var pushed: Set<String> = []

    public init() {}

    /// Returns the needs to push now (name → reason).
    public mutating func update(added: [String: String], removed: Set<String>, away: Bool) -> [String: String] {
        for name in removed {
            open[name] = nil
            pushed.remove(name)
        }
        open.merge(added) { _, new in new }
        guard away else { return [:] }
        let due = open.filter { !pushed.contains($0.key) }
        pushed.formUnion(due.keys)
        return due
    }
}
