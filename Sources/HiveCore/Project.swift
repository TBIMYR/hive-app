import Foundation

/// Projekt, Gruppe, PM und Ordnername aus Session-Name und cwd (wie hive/lib/project.js).
public enum Project {
    public static let defaultDevRoot = "\(home)/Development"

    /// Erster Ordner unter Development, sonst der letzte Pfadteil.
    public static func fromCwd(_ cwd: String, devRoot: String = defaultDevRoot) -> String {
        if cwd.isEmpty { return "" }
        let root = devRoot.hasSuffix("/") ? String(devRoot.dropLast()) : devRoot
        if cwd.hasPrefix(root + "/"), let first = cwd.dropFirst(root.count + 1).split(separator: "/").first {
            return String(first)
        }
        return (cwd as NSString).lastPathComponent
    }

    /// Präfix vor dem ersten Punkt (al.01 → al), sonst das Projekt.
    public static func groupKey(_ name: String, project: String) -> String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        return project
    }

    public static func isPm(_ name: String) -> Bool { name.hasSuffix(".pm") }

    /// Ordnername unter ~/.claude/projects: alles außer A–Z, a–z, 0–9 wird „-“, je UTF-16-Einheit wie in JS.
    public static func slug(_ cwd: String) -> String {
        let units = cwd.utf16.map { u -> UInt16 in
            let alnum = (48...57).contains(u) || (65...90).contains(u) || (97...122).contains(u)
            return alnum ? u : 45
        }
        return String(decoding: units, as: UTF16.self)
    }
}
