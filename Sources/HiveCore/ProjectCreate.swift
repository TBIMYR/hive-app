import Foundation

/// The folder step of "New Project" and its checks (spec 2026-10-08 §3). The app runs the command with `LongRun`.
public enum ProjectCreate {
    public enum Source: Equatable, Sendable { case empty, clone(String), existing }

    public struct Input: Equatable, Sendable {
        public var slug: String
        public var prefix: String
        public var folder: String
        public var source: Source
        public init(slug: String, prefix: String, folder: String, source: Source) {
            self.slug = slug; self.prefix = prefix; self.folder = folder; self.source = source
        }
    }

    /// Variables so git/gh never wait on a hidden password prompt.
    public static let quietEnv = ["GIT_TERMINAL_PROMPT": "0", "GH_PROMPT_DISABLED": "1"]

    /// argv (run through /usr/bin/env with the login PATH); nil = nothing to run.
    public static func command(_ source: Source, folder: String, hasGh: Bool) -> [String]? {
        switch source {
        case .empty:
            return ["git", "init", "-q", folder]
        case .clone(let repo):
            let r = repo.trimmingCharacters(in: .whitespaces)
            return hasGh ? ["gh", "repo", "clone", r, folder] : ["git", "clone", cloneURL(r), folder]
        case .existing:
            return nil
        }
    }

    public static func isURL(_ s: String) -> Bool { s.contains("://") || s.hasPrefix("git@") }

    /// `owner/repo` or a URL.
    public static func isRepoRef(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if isURL(t) { return true }
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }
    }

    public static func cloneURL(_ repo: String) -> String {
        isURL(repo) ? repo : "https://github.com/\(repo.hasSuffix(".git") ? String(repo.dropLast(4)) : repo).git"
    }

    /// First problem as a sentence for the dialog, nil = fine.
    public static func validate(_ i: Input, registered: [ProjectInfo], takenPrefixes: Set<String>,
                                exists: (String) -> Bool) -> String? {
        if !ProjectInfo.isValidSlug(i.slug) { return "Name: lowercase letters, digits, - and _ only." }
        if registered.contains(where: { $0.slug == i.slug }) { return "A project \(i.slug) already exists." }
        if !ProjectInfo.isValidSlug(i.prefix) { return "Prefix: lowercase letters, digits, - and _ only." }
        if takenPrefixes.contains(i.prefix) { return "Prefix \(i.prefix) is already used." }
        switch i.source {
        case .empty:
            if exists(i.folder) { return "Folder already exists: \(i.folder)" }
        case .clone(let repo):
            if !isRepoRef(repo) { return "Repository: owner/repo or a URL." }
            if exists(i.folder) { return "Folder already exists: \(i.folder)" }
        case .existing:
            if !exists(i.folder) { return "Folder does not exist: \(i.folder)" }
            if registered.contains(where: { $0.folder == i.folder }) { return "This folder is already a project." }
        }
        return nil
    }
}
