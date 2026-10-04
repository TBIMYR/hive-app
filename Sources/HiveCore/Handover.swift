import Foundation

public struct HandoverEntry: Equatable, Sendable {
    public let name: String
    public var task: String? = nil
    public var state: String? = nil
    public var updatedAt: String? = nil
    public var project: String? = nil
    /// Read error of the file (not: missing frontmatter)
    public var error: String? = nil
}

/// Reads ~/.claude/handover/*.md with frontmatter (like hive/lib/handover.js).
public enum Handover {
    public static let defaultDir = "\(home)/.claude/handover"

    // ASCII like \w in JS (Swift's \w also matches umlauts)
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
                let fields = parseFrontmatter(try readUTF8("\(dir)/\(f)")).fields
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

    /// Handover text without frontmatter for the view in the app (replaces GET /api/handover/<name>).
    /// nil if there is none. Only simple names like on the server (NAME_RE), so no path can lead out of the folder.
    public static func body(_ name: String, dir: String = defaultDir) -> String? {
        guard !name.isEmpty, !name.contains(".."),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }),
              let text = try? readUTF8("\(dir)/\(name).md") else { return nil }
        return parseFrontmatter(text).body
    }

    /// Like readFileSync(…, 'utf8') in Node: broken bytes become U+FFFD instead of discarding the whole file.
    private static func readUTF8(_ path: String) throws -> String {
        String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
    }
}
