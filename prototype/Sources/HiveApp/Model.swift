import Foundation
import SwiftUI

let hiveURL = URL(string: "http://127.0.0.1:7777")!

struct Session: Decodable, Identifiable, Equatable {
    struct Task: Decodable, Equatable {
        let text: String?
        let state: String?
        let updatedAt: String?
        let stale: Bool?
    }

    struct Said: Decodable, Equatable {
        let text: String
        let at: String?
    }

    let name: String
    let group: String?
    let project: String?
    let isPm: Bool?
    let status: String?
    let alive: Bool?
    let kind: String?
    let waitingFor: String?
    let statusUpdatedAt: String?
    let branch: String?
    let cwd: String?
    let pid: Int?
    let task: Task?
    let lastAssistant: Said?
    let hasHandover: Bool?

    var id: String { name }

    /// Gruppenschlüssel wie im Dashboard (hive gruppiert nach Namensanfang).
    var groupKey: String { group ?? name }

    /// Projektkürzel wie abbr() im Dashboard.
    var abbr: String {
        if let i = name.firstIndex(of: "."), i != name.startIndex { return String(name[..<i]) }
        let p = (project ?? group ?? "?").filter { $0.isLetter || $0.isNumber }
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

    init(_ s: Session) {
        let state = s.task?.state
        switch true {
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
    /// Namen der laufenden tmux-Sessions (einmal je Abfrage geholt)
    @Published private(set) var tmuxNames: Set<String> = []

    /// Nach dem Anlegen sofort neu laden, statt bis zu 2 s zu warten.
    func refreshSoon() { Task { await refresh() } }
    private var timer: Timer?

    private struct Payload: Decodable { let sessions: [Session] }

    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: hiveURL.appending(path: "api/state"))
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            if payload.sessions != sessions { sessions = payload.sessions }
            error = nil
            let names = await Task.detached { Tmux.listSessions() }.value
            if names != tmuxNames { tmuxNames = names }
        } catch {
            self.error = "hive nicht erreichbar (\(hiveURL.absoluteString)): \(error.localizedDescription)"
        }
        now = Date()
    }

    /// Projektname je Gruppe, wie groupLabels() im Dashboard (PM bestimmt den Namen).
    var labels: [String: String] {
        var m: [String: String] = [:]
        for s in sessions {
            if m[s.groupKey] == nil { m[s.groupKey] = s.project?.isEmpty == false ? s.project! : s.groupKey }
            if s.isPm == true, let p = s.project, !p.isEmpty { m[s.groupKey] = p }
        }
        return m
    }

    /// Farbe je Gruppe: Gruppen alphabetisch, Palette der Reihe nach.
    func color(for group: String) -> Color {
        let keys = labels.keys.sorted()
        guard let i = keys.firstIndex(of: group) else { return Color(nsColor: NSColor(hex: 0x1B1B1B)) }
        return Color(nsColor: NSColor(hex: Hive.palette[i % Hive.palette.count]))
    }

    /// Springt wie das Dashboard in den iTerm-Tab der Session. Liefert eine Fehlermeldung oder nil.
    func focusInITerm(_ s: Session) async -> String? {
        guard let pid = s.pid else { return "keine PID" }
        var req = URLRequest(url: hiveURL.appending(path: "api/focus/\(pid)"))
        req.httpMethod = "POST"
        do {
            let (data, res) = try await URLSession.shared.data(for: req)
            if (res as? HTTPURLResponse)?.statusCode == 200 { return nil }
            let reason = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["reason"] as? String
            return reason ?? "Springen nicht möglich"
        } catch {
            return "hive nicht erreichbar"
        }
    }
}
