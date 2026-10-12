import Foundation

/// A note pinned to a session: free text (Markdown), e.g. instructions that would scroll away in the terminal.
public struct Note: Equatable, Identifiable, Sendable {
    /// file name, e.g. "20261012-141502-042.md"; sorts by creation time
    public let id: String
    public var text: String
    public let created: Date?
}

/// Notes per session name, one Markdown file each under `<claudeHome>/hive/notes/<session>/`. The name is
/// the key, so notes survive `/clear` and restarts. `cc-note` writes the same files from inside a session.
public enum Notes {
    public static func root(claudeHome: String = StateBuilder.defaultClaudeHome) -> String {
        ProcessInfo.processInfo.environment["HIVE_NOTES"] ?? "\(claudeHome)/hive/notes"
    }

    /// Same rule as `cc-task`: letters, digits, `. _ # -`, no "..".
    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && name != "."
            && name.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "._#-".unicodeScalars.contains($0) }
    }

    /// Newest first. An empty file is an empty note (a fresh one); files that aren't `.md` are skipped.
    public static func list(root: String, session: String) -> [Note] {
        guard validName(session) else { return [] }
        let dir = "\(root)/\(session)"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted(by: >).compactMap { f in
            guard let text = try? String(contentsOfFile: "\(dir)/\(f)", encoding: .utf8) else { return nil }
            return Note(id: f, text: text.trimmingCharacters(in: .whitespacesAndNewlines), created: created(f))
        }
    }

    /// Number of notes per session name (sessions without notes are missing).
    public static func counts(root: String) -> [String: Int] {
        var m: [String: Int] = [:]
        for s in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where validName(s) {
            let n = list(root: root, session: s).count
            if n > 0 { m[s] = n }
        }
        return m
    }

    /// Stores a new note (empty text = a blank one to write on); nil for an invalid name.
    @discardableResult
    public static func add(root: String, session: String, text: String = "", now: Date = Date()) -> Note? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validName(session) else { return nil }
        let dir = "\(root)/\(session)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var id: String
        repeat {
            id = "\(stamp.string(from: now))-\(String(format: "%03d", Int.random(in: 0..<1000))).md"
        } while fm.fileExists(atPath: "\(dir)/\(id)")
        guard write(t, to: "\(dir)/\(id)") else { return nil }
        return Note(id: id, text: t, created: created(id))
    }

    /// Replaces a note's text. A note that was deleted meanwhile is not brought back.
    public static func save(root: String, session: String, id: String, text: String) {
        guard validName(session), validID(id), FileManager.default.fileExists(atPath: "\(root)/\(session)/\(id)") else { return }
        _ = write(text.trimmingCharacters(in: .whitespacesAndNewlines), to: "\(root)/\(session)/\(id)")
    }

    public static func remove(root: String, session: String, id: String) {
        guard validName(session), validID(id) else { return }
        try? FileManager.default.removeItem(atPath: "\(root)/\(session)/\(id)")
    }

    private static func validID(_ id: String) -> Bool { id.hasSuffix(".md") && !id.contains("/") && !id.hasPrefix(".") }

    private static func write(_ text: String, to path: String) -> Bool {
        (try? Data((text.isEmpty ? "" : text + "\n").utf8).write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// Creation time from the file name ("20261012-141502-…"), nil for other names.
    static func created(_ id: String) -> Date? {
        id.count >= 15 ? stamp.date(from: String(id.prefix(15))) : nil
    }

    /// Shorter texts are narration between work steps ("Checking the tests now"), not answers worth keeping
    public static let minReplyLength = 60

    /// The session's recent answers in full (the clipped one in `Session` is for the cards), newest first,
    /// to pick one for a note. Reads the end of the transcript, so very old answers are not offered.
    public static func recentReplies(claudeHome: String = StateBuilder.defaultClaudeHome, session: String, limit: Int = 12) -> [Said] {
        let entries = Registry.read("\(claudeHome)/sessions").entries.filter { $0.name == session && !$0.cwd.isEmpty }
        guard let e = entries.max(by: { ($0.alive ? 1 : 0, $0.startedAt) < ($1.alive ? 1 : 0, $1.startedAt) }),
              let sid = e.sessionId else { return [] }
        let dir = "\(claudeHome)/projects/\(Project.slug(e.cwd))"
        let text = Transcript.readTailFollowingContinuation(dir: dir, sessionId: sid, bytes: 1024 * 1024)
        var out: [Said] = []
        for raw in text.components(separatedBy: "\n").reversed() where raw.contains("\"assistant\"") {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                  obj["type"] as? String == "assistant" else { continue }
            let t = Transcript.textOf((obj["message"] as? [String: Any])?["content"])
            guard t.count >= minReplyLength else { continue }
            out.append(Said(text: t, at: obj["timestamp"] as? String))
            if out.count == limit { break }
        }
        return out
    }
}
