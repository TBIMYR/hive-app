import Foundation

/// Reihenfolge der angepinnten Sessions (nach Name gespeichert). Reine Funktionen, der Store speichert.
public enum Pins {
    /// Hängt den Namen ans Ende; schon angepinnte bleiben, wo sie sind.
    public static func pinning(_ name: String, in list: [String]) -> [String] {
        list.contains(name) ? list : list + [name]
    }

    /// Verschiebt `name` auf den Platz von `target` (nach rechts gezogen landet er hinter, nach links vor dem Ziel,
    /// so wie beim Ziehen über das Ziel). Unbekannte Namen ändern nichts.
    public static func moving(_ name: String, to target: String, in list: [String]) -> [String] {
        guard name != target, let from = list.firstIndex(of: name), let to = list.firstIndex(of: target) else { return list }
        var out = list
        out.remove(at: from)
        out.insert(name, at: to)
        return out
    }

    /// Je angepinntem Namen ein Eintrag aus `items`: der mit dem kleinsten Rang, bei Gleichstand der erste.
    /// Namen ohne Eintrag werden übersprungen (der Pin bleibt gespeichert).
    public static func resolve<T>(_ pinned: [String], in items: [T], name: (T) -> String, rank: (T) -> Int) -> [T] {
        pinned.compactMap { pin in
            items.filter { name($0) == pin }.min { rank($0) < rank($1) }
        }
    }
}
