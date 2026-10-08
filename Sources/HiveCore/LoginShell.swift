import Foundation

/// The user's login PATH. Launched from the Dock, the app doesn't inherit it (no Homebrew), so it is
/// fetched once from zsh.
public enum LoginShell {
    public static let path: String? = shell("print -r -- $PATH")

    /// First executable `name` in the colon-separated `path`.
    public static func findExecutable(_ name: String, path: String?) -> String? {
        for dir in (path ?? "").split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private static func shell(_ cmd: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && !s.isEmpty ? s : nil
    }
}
