import Foundation

/// Project, group, PM and folder name from session name and cwd (like hive/lib/project.js).
public enum Project {
    public static let defaultDevRoot = "\(home)/Development"

    /// First folder under Development, otherwise the last path component.
    public static func fromCwd(_ cwd: String, devRoot: String = defaultDevRoot) -> String {
        if cwd.isEmpty { return "" }
        let root = devRoot.hasSuffix("/") ? String(devRoot.dropLast()) : devRoot
        if cwd.hasPrefix(root + "/"), let first = cwd.dropFirst(root.count + 1).split(separator: "/").first {
            return String(first)
        }
        return (cwd as NSString).lastPathComponent
    }

    /// Prefix before the first dot (al.01 → al), otherwise the project.
    public static func groupKey(_ name: String, project: String) -> String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        return project
    }

    public static func isPm(_ name: String) -> Bool { name.hasSuffix(".pm") }

    /// Folder name under ~/.claude/projects: everything except A–Z, a–z, 0–9 becomes "-", per UTF-16 unit like in JS.
    public static func slug(_ cwd: String) -> String {
        let units = cwd.utf16.map { u -> UInt16 in
            let alnum = (48...57).contains(u) || (65...90).contains(u) || (97...122).contains(u)
            return alnum ? u : 45
        }
        return String(decoding: units, as: UTF16.self)
    }
}
