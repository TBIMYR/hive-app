import Foundation
import HiveCore
import SwiftUI

extension Session {
    /// Gruppenschlüssel wie im Dashboard (hive gruppiert nach Namensanfang).
    var groupKey: String { group.isEmpty ? name : group }

    /// Projektkürzel wie abbr() im Dashboard.
    var abbr: String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        let p = (project.isEmpty ? (group.isEmpty ? "?" : group) : project).filter { $0.isLetter || $0.isNumber }
        return String(p.prefix(2))
    }
}

/// Gleiche Reihenfolge wie classify() in public/index.html.
struct Status {
    let rank: Int
    let cls: String
    let label: String
    let color: Color
    let solid: Bool
    let why: String?

    /// `tmuxCommand`: was in der tmux-Session vorn läuft (nil = nicht im hive-tmux-Server).
    /// Steht die Session nicht (lebend) im Claude-Register, entscheidet dieser Befehl:
    /// Shell → „Shell“, Claude → hängt vor dem Start (meist Vertrauensabfrage), sonst anderer Agent.
    init(_ s: Session, tmuxCommand: String? = nil) {
        let state = s.task?.state
        switch true {
        case tmuxCommand.map(Tmux.isShell) == true && s.alive != true:
            self.init(2, "shell", "Shell", Hive.shell, false)
        case tmuxCommand?.hasPrefix("claude") == true && s.alive != true:
            self.init(0, "need", "wartet beim Start", Hive.need, true, why: "Start-Abfrage im Terminal beantworten")
        case tmuxCommand != nil && s.alive != true:
            self.init(2, "agent", tmuxCommand!, Hive.ink2, false)
        case s.status == "offline":
            self.init(3, "off", "offline", Hive.off, false)
        case s.status == "waiting":
            self.init(0, "need", "wartet auf dich", Hive.need, true, why: s.waitingFor ?? "Eingabe nötig")
        case s.status == "busy":
            // wer gerade arbeitet, ist nicht blockiert, auch wenn die Aufgaben-Zeile noch „blocked“ sagt
            self.init(1, "busy", "arbeitet", Hive.busy, true)
        case state == "blocked":
            self.init(0, "block", "blockiert", Hive.block, true, why: "Blockiert – braucht eine Entscheidung")
        case state == "waiting":
            self.init(2, "wait", "wartet auf Rückmeldung", Hive.wait, true)
        case s.status == "shell":
            self.init(2, "shell", "Shell", Hive.shell, false)
        default:
            self.init(2, "idle", "bereit", Hive.idle, false)
        }
    }

    private init(_ rank: Int, _ cls: String, _ label: String, _ color: Color, _ solid: Bool, why: String? = nil) {
        self.rank = rank
        self.cls = cls
        self.label = label
        self.color = color
        self.solid = solid
        self.why = why
    }
}

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var error: String?
    /// Sekundentakt für „vor x min“, auch wenn sich die Daten nicht ändern
    @Published private(set) var now = Date()
    /// Laufende tmux-Sessions mit Befehl vorn und Pane-IDs (einmal je Abfrage geholt)
    @Published private(set) var tmuxPanes = Tmux.Panes()
    /// Session-`id` → ihre tmux-Session (siehe TmuxMatch)
    @Published private(set) var tmuxOf: [String: String] = [:]

    private var timer: Timer?
    private var watcher: Watcher?
    private var refreshing = false
    private var again = false

    init() {
        Task { await refresh() }
        // Register, Handover und Gesprächsprotokolle melden Änderungen sofort; der Takt fängt
        // beendete Prozesse, tmux und die „vor x min“-Anzeige ab.
        let home = StateBuilder.defaultClaudeHome
        watcher = Watcher(paths: ["sessions", "handover", "projects"].map { "\(home)/\($0)" }) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Nach dem Anlegen sofort neu laden, statt bis zu 2 s zu warten.
    func refreshSoon() { Task { await refresh() } }

    func refresh() async {
        // Läuft schon ein Neuaufbau, danach genau einen weiteren anhängen
        if refreshing { again = true; return }
        refreshing = true
        repeat {
            again = false
            let (state, panes) = await Task.detached { (StateBuilder.build(), Tmux.panes()) }.value
            if state.sessions != sessions { sessions = state.sessions }
            error = state.sessions.isEmpty && !state.errors.isEmpty ? state.errors.joined(separator: "\n") : nil
            if panes != tmuxPanes { tmuxPanes = panes }
            let match = TmuxMatch.resolve(sessions, tmuxSessions: Set(panes.commands.keys), sessionOfPane: panes.sessionOfPane)
            if match != tmuxOf { tmuxOf = match }
            now = Date()
        } while again
        refreshing = false
    }

    /// Status mit Blick auf tmux (siehe Status.init).
    func status(_ s: Session) -> Status { Status(s, tmuxCommand: tmux(s).flatMap { tmuxPanes.commands[$0] }) }

    /// tmux-Session dieser Session im hive-Server, nil = keine.
    /// Karten, die nur aus tmux stammen (displaySessions), tragen den tmux-Namen selbst.
    func tmux(_ s: Session) -> String? {
        if let t = tmuxOf[s.id] { return t }
        let isExtra = s.pid == nil && !s.hasHandover && !sessions.contains { $0.id == s.id }
        return isExtra && tmuxPanes.commands[s.name] != nil ? s.name : nil
    }

    /// Sessions aus hive plus tmux-Sessions, die hive noch nicht kennt (kein Register, kein Handover).
    var displaySessions: [Session] {
        let known = Set(sessions.map(\.name)).union(tmuxOf.values)
        let extra = Set(tmuxPanes.commands.keys).subtracting(known).sorted().map { name in
            Session(name: name, group: SessionNaming.prefix(name) ?? name, isPm: name.hasSuffix(".pm"))
        }
        return sessions + extra
    }

    /// Projektname je Gruppe, wie groupLabels() im Dashboard (PM bestimmt den Namen).
    var labels: [String: String] {
        var m: [String: String] = [:]
        for s in sessions {
            if m[s.groupKey] == nil { m[s.groupKey] = s.project.isEmpty ? s.groupKey : s.project }
            if s.isPm, !s.project.isEmpty { m[s.groupKey] = s.project }
        }
        return m
    }

    /// Farbe je Gruppe: Gruppen alphabetisch, Palette der Reihe nach.
    func color(for group: String) -> Color {
        let keys = labels.keys.sorted()
        guard let i = keys.firstIndex(of: group) else { return Color(nsColor: NSColor(hex: 0x1B1B1B)) }
        return Color(nsColor: NSColor(hex: Hive.palette[i % Hive.palette.count]))
    }

    /// Springt in den iTerm-Tab der Session. Liefert eine Fehlermeldung oder nil.
    func focusInITerm(_ s: Session) async -> String? {
        guard let pid = s.pid else { return "keine PID" }
        if s.kind == "bg" { return "Hintergrund-Session ohne Fenster" }
        return await Task.detached { Focus.focus(pid: pid) }.value
    }

    /// Handover der Session ohne Frontmatter, wie in der Seitenleiste des Dashboards. nil, wenn keins da ist.
    func handover(_ name: String) async -> String? {
        await Task.detached { Handover.body(name) }.value
    }
}
