import Foundation

/// One project file `~/.claude/project-info/<slug>.md`: frontmatter `folder`/`prefix`, then free Markdown.
/// Every file in the folder is a known project (spec 2026-10-08).
public struct ProjectInfo: Equatable, Sendable {
    public var slug: String
    /// Absolute folder (`~` expanded)
    public var folder: String?
    public var prefix: String?
    public var body: String
    /// Other frontmatter lines, kept verbatim and in order
    public var extra: [String] = []

    public static let userHome = home
    public static let defaultDir = "\(home)/.claude/project-info"

    public init(slug: String, folder: String? = nil, prefix: String? = nil, body: String = "", extra: [String] = []) {
        self.slug = slug; self.folder = folder; self.prefix = prefix; self.body = body; self.extra = extra
    }

    public static func parse(_ text: String, slug: String, home: String = userHome) -> ProjectInfo {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return ProjectInfo(slug: slug, body: text)
        }
        var p = ProjectInfo(slug: slug, body: lines[(end + 1)...].joined(separator: "\n"))
        for line in lines[1..<end] {
            let value = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("folder:") {
                p.folder = value.isEmpty ? nil : expand(value, home: home)
            } else if line.hasPrefix("prefix:") {
                p.prefix = value.isEmpty ? nil : value
            } else {
                p.extra.append(line)
            }
        }
        return p
    }

    public func render(home: String = userHome) -> String {
        var head: [String] = []
        if let folder { head.append("folder: \(Self.abbreviate(folder, home: home))") }
        if let prefix { head.append("prefix: \(prefix)") }
        head += extra
        guard !head.isEmpty else { return body }
        return (["---"] + head + ["---"]).joined(separator: "\n") + "\n" + body
    }

    public static func template(slug: String, folder: String?, prefix: String?) -> ProjectInfo {
        ProjectInfo(slug: slug, folder: folder, prefix: prefix)
    }

    // MARK: names

    private static let slugPattern = try! Regex("^[a-z0-9][a-z0-9_-]*$")

    /// Valid project name and session prefix: lowercase, no dots, no leading `-`/`_`.
    public static func isValidSlug(_ s: String) -> Bool { (try? slugPattern.wholeMatch(in: s)) != nil }

    /// Folder name → slug: lowercase, other characters → `-`, no leading/trailing `-`/`_`. nil if nothing is left.
    public static func slug(from name: String) -> String? {
        let mapped = String(name.lowercased().map { c -> Character in
            (c.isASCII && (c.isLetter || c.isNumber)) || c == "_" || c == "-" ? c : "-"
        })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return isValidSlug(trimmed) ? trimmed : nil
    }

    // MARK: paths

    public static func expand(_ path: String, home: String = userHome) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    public static func abbreviate(_ path: String, home: String = userHome) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension ProjectInfo {
    public static func path(dir: String = defaultDir, slug: String) -> String { "\(dir)/\(slug).md" }

    /// All project files with a valid slug, sorted by slug.
    public static func loadAll(dir: String = defaultDir, home: String = userHome) -> [ProjectInfo] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.filter(isValidSlug).sorted()
            .compactMap { slug in
                (try? String(contentsOfFile: path(dir: dir, slug: slug), encoding: .utf8)).map { parse($0, slug: slug, home: home) }
            }
    }

    /// Writes atomically, creates the folder if needed.
    public func write(dir: String = defaultDir) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(render().utf8).write(to: URL(fileURLWithPath: Self.path(dir: dir, slug: slug)), options: .atomic)
    }

    /// Project whose folder is `cwd` or a parent of it; the longest folder wins.
    public static func match(cwd: String, in projects: [ProjectInfo]) -> ProjectInfo? {
        let c = trimSlash(cwd)
        return projects.filter { p in
            guard let f = p.folder.map(trimSlash), !f.isEmpty else { return false }
            return c == f || c.hasPrefix(f + "/")
        }.max { ($0.folder?.count ?? 0) < ($1.folder?.count ?? 0) }
    }

    private static func trimSlash(_ s: String) -> String { s.count > 1 && s.hasSuffix("/") ? String(s.dropLast()) : s }

    /// Project slug for a session folder, with its file if there is one. Fallback: the folder name
    /// (first folder under devRoot) as slug. nil without a cwd or without a usable name.
    public static func resolve(cwd: String, in projects: [ProjectInfo], devRoot: String = Project.defaultDevRoot)
        -> (slug: String, info: ProjectInfo?)? {
        guard !cwd.isEmpty else { return nil }
        if let m = match(cwd: cwd, in: projects) { return (m.slug, m) }
        guard let s = slug(from: Project.fromCwd(cwd, devRoot: devRoot)) else { return nil }
        return (s, projects.first { $0.slug == s })
    }

    /// Slug and folder for "Create" in the info view: the first folder under devRoot (not a worktree or
    /// subfolder), otherwise the cwd itself. nil for devRoot, home or `/`.
    public static func createDefaults(cwd: String, devRoot: String = Project.defaultDevRoot,
                                      home: String = userHome) -> (slug: String, folder: String)? {
        let c = trimSlash(cwd)
        guard !c.isEmpty, c != devRoot, c != home, c != "/" else { return nil }
        let name = Project.fromCwd(c, devRoot: devRoot)
        guard let s = slug(from: name) else { return nil }
        return (s, c.hasPrefix(devRoot + "/") ? "\(devRoot)/\(name)" : c)
    }

    /// First two letters of the name; if taken, first letter + each later letter, then a digit appended.
    public static func suggestPrefix(name: String, taken: Set<String>) -> String {
        let chars = Array(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        guard let first = chars.first else { return "" }
        for c in chars.dropFirst() where !taken.contains("\(first)\(c)") { return "\(first)\(c)" }
        let base = chars.count > 1 ? "\(first)\(chars[1])" : "\(first)"
        var n = 2
        while taken.contains("\(base)\(n)") { n += 1 }
        return "\(base)\(n)"
    }

    /// `<prefix>.pm` if that isn't running, otherwise the next `<prefix>.NN` after the highest running number.
    public static func suggestSession(prefix: String, running: Set<String>) -> String {
        if !running.contains("\(prefix).pm") { return "\(prefix).pm" }
        let used = running.compactMap { n -> Int? in
            n.hasPrefix(prefix + ".") ? Int(n.dropFirst(prefix.count + 1)) : nil
        }
        return String(format: "%@.%02d", prefix, (used.max() ?? 0) + 1)
    }
}

extension ProjectInfo {
    private static let codeURL = try! Regex(#"`(https?://[^`\s]+)`"#)

    /// Body for display: a URL written as code (`` `https://…` ``) becomes a link with code text, since
    /// Markdown never links code spans. Fenced code blocks stay as they are.
    public static func linkified(_ body: String) -> String {
        var inFence = false
        return body.components(separatedBy: "\n").map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inFence.toggle(); return line }
            guard !inFence else { return line }
            return line.replacing(codeURL) { m in
                let url = m.output[1].substring.map(String.init) ?? ""
                return "[`\(url)`](\(url))"
            }
        }.joined(separator: "\n")
    }
}
