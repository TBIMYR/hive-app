import Foundation

public struct HandoverEntry: Equatable, Sendable {
    public let name: String
    public var task: String? = nil
    public var state: String? = nil
    public var updatedAt: String? = nil
    public var project: String? = nil
    /// Lesefehler der Datei (nicht: fehlendes Frontmatter)
    public var error: String? = nil
}

/// Liest ~/.claude/handover/*.md mit Frontmatter (wie hive/lib/handover.js).
public enum Handover {
    public static let defaultDir = "\(home)/.claude/handover"

    // ASCII wie \w in JS (Swift-\w nimmt auch Umlaute)
    private static let field = try! Regex(#"^([A-Za-z_][A-Za-z0-9_-]*):\s?(.*)$"#)

    public static func parseFrontmatter(_ text: String) -> (fields: [String: String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else { return ([:], text) }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            if let m = try? field.wholeMatch(in: line), let k = m[1].substring, let v = m[2].substring {
                fields[String(k)] = String(v)
            }
        }
        return (fields, lines[(end + 1)...].joined(separator: "\n"))
    }

    public static func readDir(_ dir: String) -> [String: HandoverEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [:] }
        var map: [String: HandoverEntry] = [:]
        for f in files where f.hasSuffix(".md") {
            var e = HandoverEntry(name: String(f.dropLast(3)))
            do {
                let fields = parseFrontmatter(try String(contentsOfFile: "\(dir)/\(f)", encoding: .utf8)).fields
                e.task = fields["task"].nonEmpty
                e.state = fields["state"].nonEmpty
                e.updatedAt = fields["updated"].nonEmpty
                e.project = fields["project"].nonEmpty
            } catch {
                e.error = error.localizedDescription
            }
            map[e.name] = e
        }
        return map
    }

    /// Handover-Text ohne Frontmatter für die Ansicht in der App (ersetzt GET /api/handover/<name>).
    /// nil, wenn keins da ist. Nur einfache Namen wie im Server (NAME_RE), damit kein Pfad aus dem Ordner führt.
    public static func body(_ name: String, dir: String = defaultDir) -> String? {
        guard !name.isEmpty, !name.contains(".."),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }),
              let text = try? String(contentsOfFile: "\(dir)/\(name).md", encoding: .utf8) else { return nil }
        return parseFrontmatter(text).body
    }
}
