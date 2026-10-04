import Foundation

/// Classification of a session for the overview and notifications, same order as classify() in the dashboard.
/// Colors are set by the app (Status in HiveApp/Model.swift).
public struct SessionStatus: Equatable, Sendable {
    /// 0 needs you, 1 working, 2 ready, 3 offline
    public let rank: Int
    public let cls: String
    public let label: String
    /// Hint line in the card
    public let why: String?
    /// Text of the notification (only for rank 0)
    public let reason: String?
    /// "waiting at start": only report after a short confirmation (see AttentionTracker)
    public let waitsAtStart: Bool

    /// `tmuxCommand`: what is running in front in the tmux session (nil = not in the hive tmux server).
    /// If the session is not (alive) in the Claude registry, this command decides:
    /// shell → "Shell", Claude → stuck before start (usually a trust prompt), otherwise another agent.
    public init(_ s: Session, tmuxCommand: String? = nil) {
        let state = s.task?.state
        switch true {
        case tmuxCommand.map(Self.isShell) == true && s.alive != true:
            self.init(2, "shell", "Shell")
        case tmuxCommand?.hasPrefix("claude") == true && s.alive != true:
            let text = "Answer the start prompt in the terminal"
            self.init(0, "need", "waiting at start", why: text, reason: text, waitsAtStart: true)
        case tmuxCommand != nil && s.alive != true:
            self.init(2, "agent", tmuxCommand!)
        case s.status == "offline":
            self.init(3, "off", "offline")
        case s.status == "waiting":
            let text = s.waitingFor ?? "Input needed"
            self.init(0, "need", "waiting for you", why: text, reason: text)
        case s.status == "busy":
            // whoever is currently working is not blocked, even if the task line still says "blocked"
            self.init(1, "busy", "working")
        case state == "blocked":
            let line = s.task?.text.trimmingCharacters(in: .whitespaces) ?? ""
            self.init(0, "block", "blocked", why: "Blocked – needs a decision",
                      reason: line.isEmpty ? "needs a decision" : line)
        case s.backgroundTasks > 0:
            // main loop idle, but background agents or shell commands are still running
            self.init(1, "busy", "working in background")
        case state == "waiting":
            self.init(2, "wait", "waiting for reply")
        case s.status == "shell":
            self.init(2, "shell", "Shell")
        default:
            self.init(2, "idle", "ready")
        }
    }

    private init(_ rank: Int, _ cls: String, _ label: String, why: String? = nil, reason: String? = nil,
                 waitsAtStart: Bool = false) {
        self.rank = rank
        self.cls = cls
        self.label = label
        self.why = why
        self.reason = reason
        self.waitsAtStart = waitsAtStart
    }

    /// Command in front of a tmux pane is a shell (not an agent).
    public static func isShell(_ command: String) -> Bool {
        ["zsh", "bash", "fish", "sh", "-zsh", "-bash", "login"].contains(command)
    }
}
