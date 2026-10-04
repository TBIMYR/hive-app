import Foundation

/// Auswahl-Dialog von Claude Code auf dem Bildschirm einer Session (`tmux capture-pane -p`):
/// nummerierte Zeilen „1. …“, „2. …“, die markierte mit „❯“ davor. Grundlage der Antwort-Knöpfe:
/// geantwortet wird nur, wenn der Dialog wirklich sichtbar ist und die gewünschte Option darin steht.
public struct ScreenDialog: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let number: Int
        /// erste Zeile des Texts (umgebrochene Fortsetzungen fehlen)
        public let label: String
        /// „❯“ davor
        public let selected: Bool
    }

    /// Freigabe eines Werkzeugs: „Yes“, „Yes, and don't ask again …“, „No …“
    public enum PermissionChoice: Equatable, Sendable { case allow, alwaysAllow, deny }

    /// Was ein Knopf beantworten will.
    public enum Answer: Equatable, Sendable {
        /// Option einer AskUserQuestion über ihren Text
        case option(String)
        case permission(PermissionChoice)
    }

    public let options: [Option]
    /// bis zu 12 nicht leere Zeilen über der ersten Option (Frage, Befehl), um „derselbe Dialog?“ zu prüfen
    public let context: [String]

    static let contextLines = 12

    /// Letzter Block fortlaufend nummerierter Zeilen ab 1 (mindestens 2), nil = kein Dialog zu sehen.
    /// Eine nummerierte Liste weiter oben im Text zählt nicht, weil der Dialog immer unten steht.
    public static func parse(_ screen: String) -> ScreenDialog? {
        let lines = screen.components(separatedBy: "\n").map(stripBorder)
        var block: [Option] = []
        var start = 0
        for (i, line) in lines.enumerated() {
            guard let o = option(line) else { continue }
            if o.number == 1 {
                block = [o]
                start = i
            } else if let last = block.last, o.number == last.number + 1 {
                block.append(o)
            } else {
                block = []
            }
        }
        guard block.count >= 2 else { return nil }
        let context = lines[..<start].filter { !$0.isEmpty }.suffix(contextLines)
        return ScreenDialog(options: block, context: Array(context))
    }

    /// Rahmen „│ … │“ alter Dialoge weg, Rand weg.
    static func stripBorder(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("│") { s.removeFirst() }
        if s.hasSuffix("│") { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static let optionPattern = try! NSRegularExpression(pattern: #"^([❯›>])?\s*(\d{1,2})\.\s+(.*\S)"#)

    static func option(_ line: String) -> Option? {
        let ns = line as NSString
        guard let m = optionPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let n = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return Option(number: n, label: ns.substring(with: m.range(at: 3)), selected: m.range(at: 1).location != NSNotFound)
    }

    // MARK: Option finden

    /// Vergleichstext: ohne Rand und „…“, Leerraum zusammengefasst, klein.
    static func norm(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("…") { t.removeLast() }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func matches(screen: String, want: String) -> Bool {
        let a = norm(screen), b = norm(want)
        guard !a.isEmpty, !b.isEmpty else { return false }
        // Protokoll gekürzt („…“) oder Bildschirm umgebrochen: der Anfang reicht
        return a == b || a.hasPrefix(b) || (a.count >= 3 && b.hasPrefix(a))
    }

    /// Option mit diesem Text: genau gleich, sonst eindeutig über den Anfang. nil = nicht (eindeutig) da.
    public func option(labeled want: String) -> Option? {
        if let exact = options.first(where: { Self.norm($0.label) == Self.norm(want) }) { return exact }
        let hits = options.filter { Self.matches(screen: $0.label, want: want) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Freigabe-Zeile; nil, wenn der Dialog keine Freigabe ist (braucht eine „Yes“- und eine „No“-Zeile).
    public func permission(_ choice: PermissionChoice) -> Option? {
        func starts(_ o: Option, _ word: String) -> Bool {
            let t = Self.norm(o.label)
            return t == word || t.hasPrefix(word + ",") || t.hasPrefix(word + " ")
        }
        func always(_ o: Option) -> Bool {
            let t = Self.norm(o.label)
            return ["ask again", "always", "allow all", "during this session"].contains { t.contains($0) }
        }
        let yes = options.filter { starts($0, "yes") }
        let no = options.filter { starts($0, "no") }
        guard !yes.isEmpty, !no.isEmpty else { return nil }
        switch choice {
        case .allow: return yes.first { !always($0) }
        case .alwaysAllow: return yes.first(where: always)
        case .deny: return no.first
        }
    }

    public func pick(_ answer: Answer) -> Option? {
        switch answer {
        case .option(let label): option(labeled: label)
        case .permission(let c): permission(c)
        }
    }

    /// Option zu einer Antwort auf diesem Bildschirm; nil = Dialog nicht (mehr) so zu sehen.
    public static func pick(_ answer: Answer, on screen: String) -> Option? { parse(screen)?.pick(answer) }

    /// Derselbe Dialog (gleiche Optionen und gleicher Text darüber), egal welche Option markiert ist.
    public func sameDialog(as other: ScreenDialog) -> Bool {
        options.map { [String($0.number), $0.label] } == other.options.map { [String($0.number), $0.label] }
            && context == other.context
    }

    /// Markiert ist eine Option, die keiner der bekannten entspricht, z. B. weil gerade jemand in
    /// „Type something“ tippt. Dann nichts senden, die Ziffer landete sonst im getippten Text.
    public func selectionOutside(_ known: [String]) -> Bool {
        options.contains { o in o.selected && !known.contains { Self.matches(screen: o.label, want: $0) } }
    }
}
