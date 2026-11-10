import Foundation

/// The text of an AskUserQuestion split into blocks for the reading view: paragraphs, list items (own lines
/// "1 …", "2. …", "- …", or inline "(1) …, (2) …") and the closing question on its own.
public enum QuestionText {
    public enum Block: Equatable, Sendable {
        case paragraph(String)
        /// marker "1", "2" or "•"; title = the words up to a colon near the start ("Agenda:")
        case item(marker: String, title: String?, text: String)
        /// the last sentence, when it asks
        case ask(String)
    }

    public static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            let p = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            para = []
            if !p.isEmpty { out += inline(p) }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if let (marker, rest) = listItem(line) {
                flush()
                out.append(item(marker, rest))
            } else {
                para.append(line)
            }
        }
        flush()
        // the closing question stands apart
        if case .paragraph(let p)? = out.last, p.hasSuffix("?") {
            let (head, ask) = splitLastSentence(p)
            out.removeLast()
            if !head.isEmpty { out.append(.paragraph(head)) }
            out.append(.ask(ask))
        }
        return out
    }

    /// "1 Agenda: …", "2. …", "3) …", "- …", "• …"
    static func listItem(_ line: String) -> (String, String)? {
        if let m = line.firstMatch(of: #/^(\d{1,2})[.)]?\s+(\S.*)$/#) {
            return (String(m.1), String(m.2))
        }
        if let m = line.firstMatch(of: #/^[-•*]\s+(\S.*)$/#) { return ("•", String(m.1)) }
        return nil
    }

    static func item(_ marker: String, _ rest: String) -> Block {
        if let colon = rest.firstIndex(of: ":"), rest.distance(from: rest.startIndex, to: colon) <= 40,
           rest.index(after: colon) < rest.endIndex, rest[rest.index(after: colon)] == " " {
            let title = String(rest[...colon])
            let text = rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return .item(marker: marker, title: title, text: text)
        }
        return .item(marker: marker, title: nil, text: rest)
    }

    /// A paragraph with "(1) …, (2) …" counting up from 1: the part before, one item each, and what follows
    /// the last item's sentence.
    static func inline(_ p: String) -> [Block] {
        let marks = p.matches(of: #/\((\d{1,2})\)\s/#)
        var numbered: [Regex<(Substring, Substring)>.Match] = []
        for m in marks where Int(m.1) == numbered.count + 1 { numbered.append(m) }
        guard numbered.count >= 2 else { return [.paragraph(p)] }
        var out: [Block] = []
        let before = p[..<numbered[0].range.lowerBound].trimmingCharacters(in: .whitespaces)
        if !before.isEmpty { out.append(.paragraph(before)) }
        var after = ""
        for (i, m) in numbered.enumerated() {
            let end = i + 1 < numbered.count ? numbered[i + 1].range.lowerBound : p.endIndex
            var chunk = String(p[m.range.upperBound..<end])
            if i + 1 == numbered.count, let stop = chunk.firstMatch(of: #/[.!?]\s+(?=\S)/#) {
                after = String(chunk[stop.range.upperBound...])
                chunk = String(chunk[..<stop.range.upperBound])
            }
            chunk = chunk.trimmingCharacters(in: .whitespaces)
            for tail in [", und", " und", ", and", " and", ",", ";"] where chunk.hasSuffix(tail) { chunk.removeLast(tail.count); break }
            out.append(item(String(m.1), chunk.trimmingCharacters(in: .whitespaces)))
        }
        after = after.trimmingCharacters(in: .whitespaces)
        if !after.isEmpty { out.append(.paragraph(after)) }
        return out
    }

    static func splitLastSentence(_ p: String) -> (String, String) {
        let ends = p.dropLast().matches(of: #/[.!?:]\s+/#)
        guard let last = ends.last else { return ("", p) }
        return (p[..<last.range.lowerBound].trimmingCharacters(in: .whitespaces) + String(p[last.range].first!),
                String(p[last.range.upperBound...]))
    }
}
