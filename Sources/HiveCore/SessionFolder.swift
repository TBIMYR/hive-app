import Foundation

/// Start folder of an offline session (no registry entry), from its newest transcript under
/// ~/.claude/projects: the transcript's last `customTitle` is the session name, its first `cwd`
/// the folder Claude was started in. Reads only head and tail of each file, newest first.
public enum SessionFolder {
    public static func find(_ name: String, projectsDir: String = "\(StateBuilder.defaultClaudeHome)/projects",
                            maxAge: TimeInterval = 90 * 86_400, now: Date = Date()) -> String? {
        let fm = FileManager.default
        var files: [(path: String, date: Date)] = []
        for dir in (try? fm.contentsOfDirectory(atPath: projectsDir)) ?? [] {
            let d = "\(projectsDir)/\(dir)"
            for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".jsonl") {
                let p = "\(d)/\(f)"
                guard let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date,
                      now.timeIntervalSince(m) <= maxAge else { continue }
                files.append((p, m))
            }
        }
        for f in files.sorted(by: { $0.date > $1.date }) {
            guard let tail = read(f.path, fromEnd: true), last(#""customTitle":"([^"]*)""#, in: tail) == name,
                  let head = read(f.path, fromEnd: false), let cwd = first(#""cwd":"([^"]*)""#, in: head) else { continue }
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue { return cwd }
        }
        return nil
    }

    private static let chunk = 256 * 1024

    private static func read(_ path: String, fromEnd: Bool) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        if fromEnd, let size = try? h.seekToEnd(), size > UInt64(chunk) { try? h.seek(toOffset: size - UInt64(chunk)) }
        else { try? h.seek(toOffset: 0) }
        guard let data = try? h.read(upToCount: chunk) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
    private static func first(_ p: String, in t: String) -> String? { matches(p, in: t).first }
    private static func last(_ p: String, in t: String) -> String? { matches(p, in: t).last }
}
