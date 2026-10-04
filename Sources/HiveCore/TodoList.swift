import Foundation

/// Todo-Liste aus einer Markdown-Datei (`- [ ] Text`, `- [x] Text`, auch `* [ ]` und `[X]`).
/// Fremde Zeilen (Überschriften, Leerzeilen, Text) bleiben beim Rendern an ihrer Stelle erhalten,
/// unveränderte Aufgabenzeilen Zeichen für Zeichen. IDs gelten nur für diesen Wert (nicht in der Datei).
public struct TodoList: Equatable, Sendable {
    public struct Item: Equatable, Identifiable, Sendable {
        public let id: Int
        public var text: String
        public var done: Bool
    }

    private struct Task: Equatable, Sendable {
        var item: Item
        /// Einrückung und Aufzählungszeichen vor dem Kästchen, z. B. „  - “
        let lead: String
        /// Zeile wie gelesen; nil, sobald der Eintrag geändert wurde
        var raw: String?

        var line: String { raw ?? "\(lead)[\(item.done ? "x" : " ")] \(item.text)" }
    }

    private enum Line: Equatable, Sendable {
        case other(String)
        case task(Task)
    }

    private var lines: [Line]
    private var nextID: Int

    // Einrückung, „-“ oder „*“, Abstand, Kästchen, ein optionales Leerzeichen, Text
    private static let pattern = try! NSRegularExpression(pattern: #"^(\s*[-*]\s+)\[([ xX])\] ?(.*)$"#)

    public static func parse(_ text: String) -> TodoList {
        var lines: [Line] = []
        for (i, s) in text.components(separatedBy: "\n").enumerated() {
            let ns = s as NSString
            if let m = pattern.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                let item = Item(id: i, text: ns.substring(with: m.range(at: 3)),
                                done: ns.substring(with: m.range(at: 2)) != " ")
                lines.append(.task(Task(item: item, lead: ns.substring(with: m.range(at: 1)), raw: s)))
            } else {
                lines.append(.other(s))
            }
        }
        return TodoList(lines: lines, nextID: lines.count)
    }

    public func render() -> String {
        lines.map { line in
            switch line {
            case .other(let s): s
            case .task(let t): t.line
            }
        }.joined(separator: "\n")
    }

    /// Alle Einträge in Datei-Reihenfolge
    public var items: [Item] {
        lines.compactMap { if case .task(let t) = $0 { t.item } else { nil } }
    }

    public var open: [Item] { items.filter { !$0.done } }
    public var done: [Item] { items.filter(\.done) }
    /// Anzeige-Reihenfolge: offene, dann erledigte
    public var ordered: [Item] { open + done }

    /// Legt einen offenen Eintrag hinter dem letzten Eintrag an (ohne Einträge ans Ende, vor eine
    /// abschließende Leerzeile). Leerer Text legt nichts an. Liefert die neue ID.
    @discardableResult
    public mutating func add(_ text: String) -> Int? {
        let text = Self.clean(text)
        guard !text.isEmpty else { return nil }
        let id = nextID
        nextID += 1
        let task = Task(item: Item(id: id, text: text, done: false), lead: "- ", raw: nil)
        let at: Int
        if let last = lines.lastIndex(where: { if case .task = $0 { true } else { false } }) {
            at = last + 1
        } else if lines.last == .other("") {
            at = lines.count - 1
        } else {
            at = lines.count
        }
        lines.insert(.task(task), at: at)
        return id
    }

    public mutating func toggle(_ id: Int) {
        change(id) { $0.item.done.toggle() }
    }

    /// Neuer Text für den Eintrag; leerer Text löscht ihn.
    public mutating func edit(_ id: Int, _ text: String) {
        let text = Self.clean(text)
        guard !text.isEmpty else { return remove(id) }
        change(id) { $0.item.text = text }
    }

    public mutating func remove(_ id: Int) {
        lines.removeAll { if case .task(let t) = $0 { t.item.id == id } else { false } }
    }

    public mutating func clearDone() {
        lines.removeAll { if case .task(let t) = $0 { t.item.done } else { false } }
    }

    private mutating func change(_ id: Int, _ f: (inout Task) -> Void) {
        for i in lines.indices {
            guard case .task(var t) = lines[i], t.item.id == id else { continue }
            let before = t
            f(&t)
            if t != before { t.raw = nil }
            lines[i] = .task(t)
            return
        }
    }

    private static func clean(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}
