import Foundation

extension Session {
    /// Group key like in the dashboard (hive groups by name prefix).
    public var groupKey: String { group.isEmpty ? name : group }

    /// Last activity: the latest of the last work step and the last status change.
    public var lastActivity: Date? {
        [lastAction?.at, statusUpdatedAt].compactMap { $0.flatMap(parseISO) }.max()
    }
}

/// Order of sessions in the overview, same for all views.
public enum SessionOrder {
    /// First by rank (0 needs you … 3 offline). Rank 0: whoever has waited longest comes first (missing time first),
    /// then name. Otherwise: most recent activity first (none last), then name.
    /// Generic over the item type so the app can sort its pairs of session and status (with color) directly.
    public static func sorted<T>(_ items: [T], session: (T) -> Session, status: (T) -> SessionStatus,
                                 labels: [String: String]) -> [T] {
        items.sorted { a, b in
            before(session(a), status(a), session(b), status(b), labels: labels)
        }
    }

    static func before(_ a: Session, _ sa: SessionStatus, _ b: Session, _ sb: SessionStatus,
                       labels: [String: String]) -> Bool {
        if sa.rank != sb.rank { return sa.rank < sb.rank }
        if sa.rank == 0 {
            let ta = a.statusUpdatedAt.flatMap(parseISO) ?? .distantPast
            let tb = b.statusUpdatedAt.flatMap(parseISO) ?? .distantPast
            if ta != tb { return ta < tb }
            return a.name < b.name
        }
        let ta = a.lastActivity ?? .distantPast, tb = b.lastActivity ?? .distantPast
        if ta != tb { return ta > tb }
        return a.name < b.name
    }
}

extension SessionOrder {
    /// Target of the jump key ⌘H. `candidates`: waiting sessions (rank 0) in overview order, deduplicated by name.
    /// If the selection is waiting and the terminal is not yet focused, it stays selected (the jump just grabs
    /// focus); otherwise it moves to the next one, wrapping to the first at the end. With no candidate, the selection stays.
    public static func nextWaiting(candidates: [String], selected: String?, terminalFocused: Bool) -> String? {
        guard let first = candidates.first else { return selected }
        guard let sel = selected, let i = candidates.firstIndex(of: sel) else { return first }
        if !terminalFocused { return sel }
        return candidates[(i + 1) % candidates.count]
    }
}
