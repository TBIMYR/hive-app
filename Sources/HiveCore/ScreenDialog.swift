import Foundation

/// Choice dialog shown by Claude Code on a session's screen (`tmux capture-pane -p`):
/// numbered lines "1. …", "2. …", the selected one marked with "❯" in front. Basis for the reply buttons:
/// an answer is only sent if the dialog is actually visible and the desired option is in it.
public struct ScreenDialog: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let number: Int
        /// first line of the text (wrapped continuations are missing)
        public let label: String
        /// has "❯" in front
        public let selected: Bool
    }

    /// Approval of a tool: "Yes", "Yes, and don't ask again …", "No …"
    public enum PermissionChoice: Equatable, Sendable { case allow, alwaysAllow, deny }

    /// What a button is meant to answer.
    public enum Answer: Equatable, Sendable {
        /// Option of an AskUserQuestion, by its text
        case option(String)
        case permission(PermissionChoice)
    }

    public let options: [Option]
    /// up to 12 non-empty lines above the first option (question, command), to check "same dialog?"
    public let context: [String]

    static let contextLines = 12

    /// Last block of consecutively numbered lines starting at 1 (at least 2), nil = no dialog visible.
    /// A numbered list further up in the text doesn't count, because the dialog always sits at the bottom.
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

    /// Strips the "│ … │" border of old dialogs, and surrounding whitespace.
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

    // MARK: Finding an option

    /// Comparison text: without border and "…", whitespace collapsed, lowercased.
    static func norm(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("…") { t.removeLast() }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    static func matches(screen: String, want: String) -> Bool {
        let a = norm(screen), b = norm(want)
        guard !a.isEmpty, !b.isEmpty else { return false }
        // Transcript truncated ("…") or screen wrapped: the start is enough
        return a == b || a.hasPrefix(b) || (a.count >= 3 && b.hasPrefix(a))
    }

    /// Option with this text: exact match, otherwise unique by prefix. nil = not (uniquely) present.
    public func option(labeled want: String) -> Option? {
        if let exact = options.first(where: { Self.norm($0.label) == Self.norm(want) }) { return exact }
        let hits = options.filter { Self.matches(screen: $0.label, want: want) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Approval line; nil if the dialog isn't an approval (needs a "Yes" and a "No" line).
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

    /// Option for an answer on this screen; nil = dialog no longer looks (exactly) like this.
    public static func pick(_ answer: Answer, on screen: String) -> Option? { parse(screen)?.pick(answer) }

    /// Same dialog (same options and same text above it), regardless of which option is marked.
    public func sameDialog(as other: ScreenDialog) -> Bool {
        options.map { [String($0.number), $0.label] } == other.options.map { [String($0.number), $0.label] }
            && context == other.context
    }

    /// The selected option doesn't match any of the known ones, e.g. because someone is currently typing
    /// in "Type something". In that case send nothing, otherwise the digit would land in the typed text.
    public func selectionOutside(_ known: [String]) -> Bool {
        options.contains { o in o.selected && !known.contains { Self.matches(screen: o.label, want: $0) } }
    }
}
