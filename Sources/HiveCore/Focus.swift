import Foundation

/// Holt das iTerm-Fenster und den Tab einer Session nach vorn (wie hive/lib/focus.js).
/// Weg: PID → Terminal (ps) → iTerm-Session mit diesem tty (AppleScript).
public enum Focus {
    static let script = """
    on run argv
      set target to item 1 of argv
      tell application "iTerm2"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if tty of s is target then
                tell w to select
                tell t to select
                tell s to select
                activate
                return "ok"
              end if
            end repeat
          end repeat
        end repeat
      end tell
      return "notfound"
    end run
    """

    /// Terminal des Prozesses, z. B. /dev/ttys004; nil ohne Terminal.
    public static func tty(of pid: Int) -> String? {
        let r = Shell.run("/bin/ps", ["-o", "tty=", "-p", String(pid)])
        let tty = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard r.status == 0, !tty.isEmpty, tty != "??" else { return nil }
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// nil = Tab ist vorn, sonst der Grund.
    public static func focus(pid: Int) -> String? {
        guard let tty = tty(of: pid) else { return "Session has no terminal" }
        let r = Shell.run("/usr/bin/osascript", ["-e", script, tty])
        if r.status != 0 { return r.err.isEmpty ? "osascript error \(r.status)" : r.err }
        return r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "ok" ? nil : "No iTerm tab with \(tty)"
    }
}
