import Foundation

/// Einordnung einer Session für Übersicht und Mitteilungen, gleiche Reihenfolge wie classify() im Dashboard.
/// Farben setzt die App (Status in HiveApp/Model.swift).
public struct SessionStatus: Equatable, Sendable {
    /// 0 braucht dich, 1 arbeitet, 2 bereit, 3 offline
    public let rank: Int
    public let cls: String
    public let label: String
    /// Hinweiszeile in der Karte
    public let why: String?
    /// Text der Mitteilung (nur bei Rang 0)
    public let reason: String?
    /// „wartet beim Start“: erst nach kurzer Bestätigung melden (siehe AttentionTracker)
    public let waitsAtStart: Bool

    /// `tmuxCommand`: was in der tmux-Session vorn läuft (nil = nicht im hive-tmux-Server).
    /// Steht die Session nicht (lebend) im Claude-Register, entscheidet dieser Befehl:
    /// Shell → „Shell“, Claude → hängt vor dem Start (meist Vertrauensabfrage), sonst anderer Agent.
    public init(_ s: Session, tmuxCommand: String? = nil) {
        let state = s.task?.state
        switch true {
        case tmuxCommand.map(Self.isShell) == true && s.alive != true:
            self.init(2, "shell", "Shell")
        case tmuxCommand?.hasPrefix("claude") == true && s.alive != true:
            let text = "Start-Abfrage im Terminal beantworten"
            self.init(0, "need", "wartet beim Start", why: text, reason: text, waitsAtStart: true)
        case tmuxCommand != nil && s.alive != true:
            self.init(2, "agent", tmuxCommand!)
        case s.status == "offline":
            self.init(3, "off", "offline")
        case s.status == "waiting":
            let text = s.waitingFor ?? "Eingabe nötig"
            self.init(0, "need", "wartet auf dich", why: text, reason: text)
        case s.status == "busy":
            // wer gerade arbeitet, ist nicht blockiert, auch wenn die Aufgaben-Zeile noch „blocked“ sagt
            self.init(1, "busy", "arbeitet")
        case state == "blocked":
            let line = s.task?.text.trimmingCharacters(in: .whitespaces) ?? ""
            self.init(0, "block", "blockiert", why: "Blockiert – braucht eine Entscheidung",
                      reason: line.isEmpty ? "braucht eine Entscheidung" : line)
        case state == "waiting":
            self.init(2, "wait", "wartet auf Rückmeldung")
        case s.status == "shell":
            self.init(2, "shell", "Shell")
        default:
            self.init(2, "idle", "bereit")
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

    /// Befehl vorn in einer tmux-Pane ist eine Shell (kein Agent).
    public static func isShell(_ command: String) -> Bool {
        ["zsh", "bash", "fish", "sh", "-zsh", "-bash", "login"].contains(command)
    }
}
