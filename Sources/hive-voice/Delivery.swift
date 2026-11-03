import Foundation
import HiveCore

/// Types a message into a running session, the same way Hive's reply field does (tmux send-keys).
enum Delivery {
    static let tmux: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    static let socket = ProcessInfo.processInfo.environment["HIVE_TMUX"] ?? "hive"

    /// nil = sent, otherwise why not (in German, it is read aloud).
    static func send(_ text: String, to name: String, sessions: [Session]) -> String? {
        guard let s = sessions.first(where: { $0.name == name }) else { return "Eine Session \(name) kenne ich nicht." }
        guard s.alive else { return "\(name) läuft gerade nicht." }
        guard let tmux else { return "tmux fehlt." }
        guard run(tmux, ["-L", socket, "has-session", "-t", SessionControl.target(name)]) == 0 else {
            return "\(name) läuft nicht in Hive, dort kann ich nichts eintippen."
        }
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        for args in SessionControl.typeArgs(oneLine, into: name) where run(tmux, ["-L", socket] + args) != 0 {
            return "Das Eintippen bei \(name) hat nicht geklappt."
        }
        return nil
    }

    private static func run(_ exe: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "TMUX")
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
