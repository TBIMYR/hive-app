import Foundation
import HiveCore
import SwiftUI

extension Session {
    /// Project abbreviation like abbr() in the dashboard.
    var abbr: String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        let p = (project.isEmpty ? (group.isEmpty ? "?" : group) : project).filter { $0.isLetter || $0.isNumber }
        return String(p.prefix(2))
    }
}

/// Classification from HiveCore (SessionStatus) plus color for the card.
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
    /// Per-second tick for "x min ago", even when the data doesn't change
    @Published private(set) var now = Date()
    /// Running tmux sessions with their command and pane IDs (fetched once per query)
    @Published private(set) var tmuxPanes = Tmux.Panes()
    /// Session `id` → its tmux session (see TmuxMatch)
    @Published private(set) var tmuxOf: [String: String] = [:]
    /// Selected session (name). `--select <name>` selects one at startup (for trying things out).
    @Published var selected: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--select"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    /// Notifications and dock badge; the store holds it because the notification center only holds its delegate weakly
    let notifier = Notifier()
    /// Favorites (names), stored under `pinned` (formerly the "Pinned" bar; old pins thereby become favorites)
    @Published private(set) var favorites: [String] = UserDefaults.standard.stringArray(forKey: "pinned") ?? []
    /// Preset for the "New Session" dialog (nil = closed)
    @Published var newPreset: NewSessionPreset?
    /// Each increment asks the terminal of the selection for keyboard focus (see TmuxTerminal)
    @Published private(set) var focusRequest = 0
    /// Open confirmation for "Close…"/"Restart…"
    @Published var closeRequest: CloseRequest?
    /// Open confirmation for "Force Quit…"
    @Published var forceQuitRequest: ForceQuitRequest?
    /// Notice shown as an alert (e.g. session not finished after 15 s)
    @Published var notice: String?
    /// Incremented after a restart: the terminal attaches to the new tmux session of the same name
    @Published private(set) var terminalEpoch = 0

    private var timer: Timer?
    private var watcher: Watcher?
    private var refreshing = false
    private var again = false

    init() {
        notifier.onSelect = { [weak self] name in self?.selected = name }
        Task { await refresh() }
        // Register, handover, and transcripts report changes immediately; the tick catches
        // finished processes, tmux, and the "x min ago" display.
        let home = StateBuilder.defaultClaudeHome
        watcher = Watcher(paths: ["sessions", "handover", "projects"].map { "\(home)/\($0)" }) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Reload immediately after creating, instead of waiting up to 2 s.
    func refreshSoon() { Task { await refresh() } }

    func refresh() async {
        // If a rebuild is already running, queue exactly one more after it
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

    /// Status with a view of tmux (see Status.init).
    func status(_ s: Session) -> Status { Status(s, tmuxCommand: tmux(s).flatMap { tmuxPanes.commands[$0] }) }

    /// Sessions with rank 0 by name, for notifications and the dock badge. For duplicate names
    /// the first entry with rank 0 counts (a dead entry doesn't hide the live one).
    var needs: [String: AttentionTracker.Need] {
        var m: [String: AttentionTracker.Need] = [:]
        for s in displaySessions where m[s.name] == nil {
            let st = status(s).core
            guard st.rank == 0 else { continue }
            m[s.name] = AttentionTracker.Need(reason: st.reason ?? st.label, confirmAfter: st.waitsAtStart ? 3 : 0)
        }
        return m
    }

    /// Jump key ⌘H: to the longest-waiting session, cursor into the terminal; each further press to the next.
    func jumpToWaiting() {
        let waiting = displaySessions.map { ($0, status($0)) }.filter { $0.1.rank == 0 }
        var seen = Set<String>()
        let names = SessionOrder.sorted(waiting, session: { $0.0 }, status: { $0.1.core }, labels: labels)
            .map(\.0.name).filter { seen.insert($0).inserted }
        guard !names.isEmpty else { return }
        // without a tmux terminal (e.g. iTerm) there's no focus to grab: then move straight to the next one
        let hasTerminal = displaySessions.contains { $0.name == selected && tmux($0) != nil }
        let focused = NSApp.keyWindow?.firstResponder is HiveTerminalView || !hasTerminal
        selected = SessionOrder.nextWaiting(candidates: names, selected: selected, terminalFocused: focused)
        focusRequest += 1
    }

    /// tmux session of this session in the hive server, nil = none.
    /// Cards that come only from tmux (displaySessions) carry the tmux name itself.
    func tmux(_ s: Session) -> String? {
        if let t = tmuxOf[s.id] { return t }
        let isExtra = s.pid == nil && !s.hasHandover && !sessions.contains { $0.id == s.id }
        return isExtra && tmuxPanes.commands[s.name] != nil ? s.name : nil
    }

    /// Sessions from hive plus tmux sessions that hive doesn't know yet (no register, no handover).
    var displaySessions: [Session] {
        let known = Set(sessions.map(\.name)).union(tmuxOf.values)
        let extra = Set(tmuxPanes.commands.keys).subtracting(known).sorted().map { name in
            Session(name: name, group: SessionNaming.prefix(name) ?? name, isPm: name.hasSuffix(".pm"))
        }
        return sessions + extra
    }

    func isFavorite(_ name: String) -> Bool { favorites.contains(name) }

    /// Star or right-click menu: toggle favorite on/off, stored under `pinned`.
    func toggleFavorite(_ name: String) {
        favorites = Favorites.toggling(name, in: favorites)
        UserDefaults.standard.set(favorites, forKey: "pinned")
    }

    /// Project name per group, like groupLabels() in the dashboard (the PM determines the name).
    var labels: [String: String] {
        var m: [String: String] = [:]
        for s in sessions {
            if m[s.groupKey] == nil { m[s.groupKey] = s.project.isEmpty ? s.groupKey : s.project }
            if s.isPm, !s.project.isEmpty { m[s.groupKey] = s.project }
        }
        return m
    }

    /// Color per group: groups alphabetically, palette in order. Fetch once for many sessions.
    func groupColors(_ labels: [String: String]) -> [String: Color] {
        var m: [String: Color] = [:]
        for (i, key) in labels.keys.sorted().enumerated() {
            m[key] = Color(nsColor: NSColor(hex: Hive.palette[i % Hive.palette.count]))
        }
        return m
    }

    /// Color for groups without a project name (pure tmux sessions)
    static let fallbackColor = Color(nsColor: NSColor(hex: 0x1B1B1B))

    func color(for group: String) -> Color { groupColors(labels)[group] ?? Self.fallbackColor }

    /// Jumps to the session's iTerm tab. Returns an error message or nil.
    func focusInITerm(_ s: Session) async -> String? {
        guard let pid = s.pid else { return "No PID" }
        if s.kind == "bg" { return "Background session without a window" }
        return await Task.detached { Focus.focus(pid: pid) }.value
    }

    /// The session's handover without frontmatter, like in the dashboard's sidebar. nil if there isn't one.
    func handover(_ name: String) async -> String? {
        await Task.detached { Handover.body(name) }.value
    }

    // MARK: Control session (only sessions in tmux)

    /// Reply field of the card: type text and send. Returns an error message or nil.
    func reply(_ raw: String, to s: Session) async -> String? {
        guard let text = SessionControl.replyText(raw) else { return nil }
        guard let t = tmux(s) else { return "Not running in Hive" }
        let e = await Task.detached { Tmux.type(text, into: t) }.value
        refreshSoon()
        return e
    }

    /// Reply button in the card (multiple-choice question or approval). Returns a message or nil.
    func answer(_ a: ScreenDialog.Answer, known: [String], to s: Session) async -> String? {
        guard let t = tmux(s) else { return "Not running in Hive" }
        let e = await Task.detached { Tmux.answer(a, known: known, in: t) }.value
        refreshSoon()
        return e
    }

    /// Dialog currently showing on the session's screen (read-only), nil = none.
    func dialog(_ s: Session) async -> ScreenDialog? {
        guard let t = tmux(s) else { return nil }
        return await Task.detached { Tmux.capture(t).flatMap(ScreenDialog.parse) }.value
    }

    /// "Write Handover" menu item: `/handover` + Enter.
    func writeHandover(_ s: Session) {
        guard let t = tmux(s) else { return }
        Task {
            if let e = await Task.detached(operation: { Tmux.type("/handover", into: t) }).value {
                notice = "Could not write to \(s.name): \(e)"
            }
            refreshSoon()
        }
    }

    /// "Close…"/"Restart…" menu item: get confirmation first (ContentView shows the dialog).
    func requestClose(_ s: Session, restart: Bool) {
        guard let t = tmux(s) else { return }
        closeRequest = CloseRequest(session: s, tmux: t, restart: restart)
    }

    /// Type `/exit`, wait up to 15 s for the agent to be gone, then end the tmux session.
    /// On restart, afterwards start `claude -n <name>` in the same folder under the same name.
    func close(_ r: CloseRequest) {
        let s = r.session, t = r.tmux
        let dir = s.cwd ?? tmuxPanes.paths[t]
        Task {
            if let e = await Task.detached(operation: { Tmux.type("/exit", into: t) }).value {
                notice = "Could not write to \(s.name): \(e)"
                return
            }
            let gone = await SessionControl.waitUntil(timeout: 15, interval: 0.5) {
                await self.refresh()
                let aliveNow = self.sessions.first { $0.id == s.id }?.alive == true
                return SessionControl.hasExited(wasAlive: s.alive, aliveNow: aliveNow,
                                                paneCommand: self.tmuxPanes.commands[t])
            }
            guard gone else {
                notice = "\(s.name) is still running after 15 s. Its terminal stays open."
                return
            }
            if tmuxPanes.commands[t] != nil,
               let e = await Task.detached(operation: { Tmux.kill(t) }).value {
                notice = "Could not close the terminal of \(s.name): \(e)"
                return
            }
            if r.restart {
                guard let dir, !dir.isEmpty else {
                    notice = "No folder known for \(s.name), so it was not restarted."
                    return
                }
                if let e = await Task.detached(operation: { Tmux.newSession(name: s.name, dir: dir, submit: true) }).value {
                    notice = "Could not restart \(s.name): \(e)"
                    return
                }
                // same tmux name: the terminal needs to reattach
                terminalEpoch += 1
                selected = s.name
            }
            await refresh()
        }
    }

    /// "Force Quit…" menu item: remember the process (PID + start time), then confirm.
    func requestForceQuit(_ s: Session) {
        guard let pid = s.pid else { return }
        guard let started = ProcessControl.startTime(pid) else {
            notice = "\(s.name) is no longer running."
            refreshSoon()
            return
        }
        forceQuitRequest = ForceQuitRequest(session: s, pid: pid, started: started)
    }

    /// Ends the process by PID (SIGTERM, then SIGKILL). Its terminal, if any, stays open.
    func forceQuit(_ r: ForceQuitRequest) {
        Task {
            if let e = await ProcessControl.forceQuit(pid: r.pid, started: r.started) {
                notice = "Could not force quit \(r.session.name): \(e)"
            }
            await refresh()
        }
    }
}

/// Confirmation for "Force Quit…" (ContentView shows the dialog).
struct ForceQuitRequest: Identifiable {
    let session: Session
    let pid: Int
    let started: Date

    var id: String { session.id }
    var title: String { "Force quit \(session.name)?" }
    var message: String {
        let what = "Ends the process (PID \(pid)) without /exit. Unsaved work in the session is lost."
        let warnings = SessionControl.closeWarnings(session).map { $0 + "." }
        return ([what] + warnings).joined(separator: "\n")
    }
}

/// Confirmation for "Close…"/"Restart…" (ContentView shows the dialog).
struct CloseRequest: Identifiable {
    let session: Session
    /// tmux session at the time of the request
    let tmux: String
    let restart: Bool

    var id: String { session.id }
    var title: String { "\(restart ? "Restart" : "Close") \(session.name)?" }
    var message: String {
        let what = restart
            ? "Types /exit, closes its terminal and starts claude -n \(session.name) again in the same folder."
            : "Types /exit and closes its terminal."
        let warnings = SessionControl.closeWarnings(session).map { $0 + "." }
        return ([what] + warnings).joined(separator: "\n")
    }
}
