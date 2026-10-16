import Foundation

/// One notepad per session name: a Markdown file `<claudeHome>/hive/notes/<session>.md`. The name is the
/// key, so the notes survive `/clear` and restarts. `cc-note` appends to the same file from inside a session.
public enum Notes {
    public static func root(claudeHome: String = StateBuilder.defaultClaudeHome) -> String {
        ProcessInfo.processInfo.environment["HIVE_NOTES"] ?? "\(claudeHome)/hive/notes"
    }

    /// Key of the notepad shared by all sessions (a hidden file, so it never counts as a session's notes)
    public static let global = ".global"

    /// Between two entries that were appended (same as in `cc-note`)
    public static let separator = "\n\n---\n\n"

    /// Same rule as `cc-task`: letters, digits, `. _ # -`, no "..".
    public static func validName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..") && name != "."
            && name.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || "._#-".unicodeScalars.contains($0) }
    }

    private static func path(_ root: String, _ session: String) -> String { "\(root)/\(session).md" }

    /// The session's notes, "" if there are none.
    public static func read(root: String, session: String) -> String {
        guard validName(session), let text = try? String(contentsOfFile: path(root, session), encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the session's notes; empty text removes the file.
    public static func write(root: String, session: String, text: String) {
        guard validName(session) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            try? FileManager.default.removeItem(atPath: path(root, session))
        } else {
            try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
            try? Data((t + "\n").utf8).write(to: URL(fileURLWithPath: path(root, session)), options: .atomic)
        }
    }

    /// Adds an entry below what is there, set apart by a line.
    public static func append(root: String, session: String, text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let old = read(root: root, session: session)
        write(root: root, session: session, text: old.isEmpty ? t : old + separator + t)
    }

    /// Names of the sessions that have notes.
    public static func sessions(root: String) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return Set(files.compactMap { f in
            guard f.hasSuffix(".md"), !f.hasPrefix(".") else { return nil }
            let name = String(f.dropLast(3))
            return validName(name) && !read(root: root, session: name).isEmpty ? name : nil
        })
    }

    /// Earlier every note was a file of its own in `<root>/<session>/`. Those go into the session's notepad,
    /// oldest first and above what is already there; the folder is kept under `<root>/.old/`.
    public static func migrate(root: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where validName(name) && !name.hasPrefix(".") {
            let dir = "\(root)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") }.sorted()
            let texts = files.compactMap { try? String(contentsOfFile: "\(dir)/\($0)", encoding: .utf8) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let old = read(root: root, session: name)
            write(root: root, session: name, text: (texts + (old.isEmpty ? [] : [old])).joined(separator: separator))
            try? fm.createDirectory(atPath: "\(root)/.old", withIntermediateDirectories: true)
            var dest = "\(root)/.old/\(name)", n = 1
            while fm.fileExists(atPath: dest) { n += 1; dest = "\(root)/.old/\(name)-\(n)" }
            try? fm.moveItem(atPath: dir, toPath: dest)
        }
    }
}
