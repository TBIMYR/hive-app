import Foundation
import HiveCore
import VoiceKit

/// Types a message into a running session, the same way Hive's reply field does (tmux send-keys).
/// If the session shows a choice dialog, it picks the option instead, like Hive's answer buttons.
enum Delivery {
    static let tmux: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    static let socket = ProcessInfo.processInfo.environment["HIVE_TMUX"] ?? "hive"

    /// nil = sent, otherwise why not (in German, it is read aloud).
    static func send(_ text: String, to name: String, sessions: [Session]) -> String? {
        guard let s = sessions.first(where: { $0.name == name }) else { return "Eine Session \(name) kenne ich nicht." }
        guard s.alive else { return "\(name) läuft gerade nicht." }
        guard tmux != nil else { return "tmux fehlt." }
        guard run(["has-session", "-t", SessionControl.target(name)]).status == 0 else {
            return "\(name) läuft nicht in Hive, dort kann ich nichts eintippen."
        }
        if let dialog = dialog(name) { return answer(text, dialog, in: name) }
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        for args in SessionControl.typeArgs(oneLine, into: name) where run(args).status != 0 {
            return "Das Eintippen bei \(name) hat nicht geklappt."
        }
        return nil
    }

    /// The choice dialog on the session's screen, if one is visible.
    static func dialog(_ name: String) -> ScreenDialog? {
        let r = run(SessionControl.captureArgs(name))
        return r.status == 0 ? ScreenDialog.parse(r.output) : nil
    }

    /// Same steps as Hive's answer buttons: type the digit, and Enter only if the same dialog is still there
    /// with that option marked.
    private static func answer(_ text: String, _ before: ScreenDialog, in name: String) -> String? {
        guard let option = DialogReply.pick(text, in: before) else {
            return "\(name) zeigt eine Auswahl, da passt \"\(text)\" nicht. Sag mir die Nummer."
        }
        guard run(SessionControl.keyArgs(String(option.number), into: name)).status == 0 else {
            return "Die Auswahl bei \(name) hat nicht geklappt."
        }
        log("\(name): picked \(option.number). \(option.label)")
        Thread.sleep(forTimeInterval: 0.3)
        guard let after = dialog(name), after.options.map(\.label) == before.options.map(\.label) else { return nil }
        guard after.sameDialog(as: before), after.options.filter(\.selected).map(\.number) == [option.number] else {
            return "Bei \(name) hat sich der Dialog geändert, schau bitte selbst."
        }
        return run(SessionControl.keyArgs("Enter", into: name)).status == 0 ? nil : "Die Auswahl bei \(name) hat nicht geklappt."
    }

    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        guard let tmux else { return (-1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tmux)
        p.arguments = ["-L", socket] + args
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "TMUX")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
