import Foundation

extension Session {
    /// Gruppenschlüssel wie im Dashboard (hive gruppiert nach Namensanfang).
    public var groupKey: String { group.isEmpty ? name : group }
}

/// Reihenfolge der Sessions in der Übersicht, gleich für alle Ansichten.
public enum SessionOrder {
    /// Erst nach Rang (0 braucht dich … 3 offline). Rang 0: wer am längsten wartet, zuerst (fehlende Zeit ganz vorn),
    /// dann Name. Sonst: „wartet auf Rückmeldung“ zuerst, dann Projektname, PM vor Workern, dann Name.
    /// Allgemein über den Elementtyp, damit die App ihre Paare aus Session und Status (mit Farbe) direkt sortiert.
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
        if (sa.cls == "wait") != (sb.cls == "wait") { return sa.cls == "wait" }
        let la = labels[a.groupKey] ?? "", lb = labels[b.groupKey] ?? ""
        if la != lb { return la.localizedCompare(lb) == .orderedAscending }
        if a.isPm != b.isPm { return a.isPm }
        return a.name < b.name
    }
}

extension SessionOrder {
    /// Ziel der Sprung-Taste ⌘H. `candidates`: wartende Sessions (Rang 0) in Übersichts-Reihenfolge, nach Name
    /// entdoppelt. Ist die Auswahl wartend und das Terminal noch nicht fokussiert, bleibt sie (der Sprung holt nur
    /// den Fokus); sonst geht es zur nächsten, am Ende wieder zur ersten. Ohne Kandidatin bleibt die Auswahl.
    public static func nextWaiting(candidates: [String], selected: String?, terminalFocused: Bool) -> String? {
        guard let first = candidates.first else { return selected }
        guard let sel = selected, let i = candidates.firstIndex(of: sel) else { return first }
        if !terminalFocused { return sel }
        return candidates[(i + 1) % candidates.count]
    }
}
