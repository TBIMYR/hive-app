import Foundation

/// A session's answer split into blocks for the full cards: headings, paragraphs, list items (with their
/// indented continuation lines) and code, where code also takes fenced blocks and tables, set as written.
public enum AnswerText {
    public enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph(String)
        /// marker "1", "2" or "•"; `depth` 1 for an indented item
        case item(marker: String, text: String, depth: Int)
        case code(String)
    }

    public static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        var code: [String]? = nil
        func flush() {
            let p = para.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            para = []
            if !p.isEmpty { out.append(.paragraph(p)) }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code {
                    out.append(.code(c.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code!.append(raw); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("|") {
                flush()
                // rows of one table stay one block
                if case .code(let c)? = out.last, c.hasPrefix("|") { out[out.count - 1] = .code(c + "\n" + line) }
                else { out.append(.code(line)) }
                continue
            }
            if let m = line.firstMatch(of: #/^#{1,6}\s+(.+)$/#) {
                flush()
                out.append(.heading(String(m.1)))
            } else if let (marker, rest) = QuestionText.listItem(line) {
                flush()
                let indent = raw.prefix(while: { $0 == " " }).count
                out.append(.item(marker: marker, text: rest, depth: indent >= 2 ? 1 : 0))
            } else if raw.hasPrefix(" "), para.isEmpty, case .item(let m, let t, let d)? = out.last {
                // a wrapped list item goes on in an indented line
                out[out.count - 1] = .item(marker: m, text: t + " " + line, depth: d)
            } else {
                para.append(line)
            }
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }
}
