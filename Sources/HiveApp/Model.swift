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

/// Einordnung aus HiveCore (SessionStatus) plus Farbe für die Karte.
struct Status {
    let core: SessionStatus
    let color: Color
    let solid: Bool

    var rank: Int { core.rank }
    var cls: String { core.cls }
    var label: String { core.label }
    var why: String? { core.why }

    private static let look: [String: (Color, Bool)] = [
        "need": (Hive.need, true), "block": (Hive.block, true), "busy": (Hive.busy, true),
        "wait": (Hive.wait, true), "shell": (Hive.shell, false), "agent": (Hive.ink2, false),
        "off": (Hive.off, false), "idle": (Hive.idle, false),
    ]

    init(_ s: Session, tmuxCommand: String? = nil) {
        core = SessionStatus(s, tmuxCommand: tmuxCommand)
        (color, solid) = Self.look[core.cls] ?? (Hive.idle, false)
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
    /// Ausgewählte Session (Name). `--select <name>` wählt beim Start eine (zum Ausprobieren).
    @Published var selected: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--select"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    /// Mitteilungen und Dock-Zahl; der Store hält ihn, weil das Mitteilungszentrum seinen Delegate nur schwach hält
    let notifier = Notifier()

    private var timer: Timer?
    private var watcher: Watcher?
    private var refreshing = false
    private var again = false

    init() {
        notifier.onSelect = { [weak self] name in self?.selected = name }
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
            notifier.update(needs, selected: selected)
            now = Date()
        } while again
        refreshing = false
    }

    /// Status mit Blick auf tmux (siehe Status.init).
    func status(_ s: Session) -> Status { Status(s, tmuxCommand: tmux(s).flatMap { tmuxPanes.commands[$0] }) }

    /// Sessions mit Rang 0 nach Name, für Mitteilungen und Dock-Zahl. Bei doppelten Namen
    /// zählt der erste Eintrag mit Rang 0 (ein toter Eintrag verdeckt den lebenden nicht).
    var needs: [String: AttentionTracker.Need] {
        var m: [String: AttentionTracker.Need] = [:]
        for s in displaySessions where m[s.name] == nil {
            let st = status(s).core
            guard st.rank == 0 else { continue }
            m[s.name] = AttentionTracker.Need(reason: st.reason ?? st.label, confirmAfter: st.waitsAtStart ? 3 : 0)
        }
        return m
    }

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
