import Foundation

/// Where a note's Markdown gets which look, enough for instructions: headings, list markers, bold, inline
/// code and fenced code. The note editor styles its text with these spans while one types, and hides the
/// markup characters of every line the cursor is not on.
public enum NoteMarkdown {
    public enum Kind: Equatable, Sendable {
        /// whole heading line, level 1…6
        case heading(Int)
        case bold
        /// inline code, without the backticks
        case code
        /// a line inside a fenced block
        case codeBlock
        /// "-", "*", "1." in front of a list item
        case listMarker
        /// whole line of a list item; `prefix` is its indentation, marker and the space after it, so wrapped
        /// lines can be indented to where the item's text starts
        case listItem(prefix: NSRange)
        /// characters that only carry meaning (`#`, `**`, backticks, fence lines); shown only while the cursor
        /// is inside `scope`
        case markup(scope: NSRange)
    }

    public struct Span: Equatable, Sendable {
        public let range: NSRange
        public let kind: Kind
    }

    private static let headingPattern = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+(?=\S)"#)
    private static let listPattern = try! NSRegularExpression(pattern: #"^[ \t]*([-*+]|\d{1,3}[.)])[ \t]+"#)
    private static let codePattern = try! NSRegularExpression(pattern: #"`([^`]+)`"#)
    private static let boldPattern = try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)

    /// Ranges are UTF-16 offsets into `text` (as NSString / NSTextStorage use them).
    public static func spans(_ text: String) -> [Span] {
        let ns = text as NSString
        var out: [Span] = []
        /// open fence: its line and where the block starts
        var fence: (line: NSRange, start: Int)?
        var fenceBody: [NSRange] = []
        var at = 0
        while at < ns.length {
            let full = ns.lineRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(full)
            // the line without its line break
            var line = full
            while line.length > 0, let c = UnicodeScalar(ns.character(at: NSMaxRange(line) - 1)), CharacterSet.newlines.contains(c) {
                line.length -= 1
            }
            let trimmed = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix("```") {
                    let scope = NSRange(location: open.start, length: NSMaxRange(line) - open.start)
                    out.append(Span(range: open.line, kind: .markup(scope: scope)))
                    out += fenceBody.map { Span(range: $0, kind: .codeBlock) }
                    out.append(Span(range: line, kind: .markup(scope: scope)))
                    fence = nil
                    fenceBody = []
                } else if line.length > 0 {
                    fenceBody.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                fence = (line, line.location)
                continue
            }
            if line.length == 0 { continue }
            if let m = headingPattern.firstMatch(in: text, range: line) {
                out.append(Span(range: line, kind: .heading(m.range(at: 1).length)))
                out.append(Span(range: m.range, kind: .markup(scope: line)))
            } else if let m = listPattern.firstMatch(in: text, range: line) {
                out.append(Span(range: line, kind: .listItem(prefix: m.range)))
                out.append(Span(range: m.range(at: 1), kind: .listMarker))
            }
            var codeRanges: [NSRange] = []
            for m in codePattern.matches(in: text, range: line) {
                codeRanges.append(m.range)
                out.append(Span(range: m.range(at: 1), kind: .code))
                out.append(Span(range: NSRange(location: m.range.location, length: 1), kind: .markup(scope: line)))
                out.append(Span(range: NSRange(location: NSMaxRange(m.range) - 1, length: 1), kind: .markup(scope: line)))
            }
            for m in boldPattern.matches(in: text, range: line)
            where !codeRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                out.append(Span(range: m.range(at: 1), kind: .bold))
                out.append(Span(range: NSRange(location: m.range.location, length: 2), kind: .markup(scope: line)))
                out.append(Span(range: NSRange(location: NSMaxRange(m.range) - 2, length: 2), kind: .markup(scope: line)))
            }
        }
        // an unclosed fence (still being typed): its lines already look like code, the fence stays visible
        if fence != nil { out += fenceBody.map { Span(range: $0, kind: .codeBlock) } }
        return out
    }

    /// Whether markup with this scope is shown: only while the selection touches the scope (or sits at its end).
    public static func showsMarkup(scope: NSRange, selection: NSRange?) -> Bool {
        guard let s = selection else { return false }
        return s.location <= NSMaxRange(scope) && NSMaxRange(s) >= scope.location
    }
}
