import Foundation
import SwiftUI

let hiveURL = URL(string: "http://127.0.0.1:7777")!

struct Session: Decodable, Identifiable, Equatable {
    struct Task: Decodable, Equatable {
        let text: String?
        let state: String?
    }

    let name: String
    let group: String?
    let project: String?
    let isPm: Bool?
    let status: String?
    let alive: Bool?
    let kind: String?
    let waitingFor: String?
    let branch: String?
    let cwd: String?
    let pid: Int?
    let task: Task?

    var id: String { name }
}

/// Gleiche Reihenfolge wie classify() in public/index.html.
struct Status {
    let rank: Int
    let label: String
    let color: Color
    let why: String?

    init(_ s: Session) {
        let state = s.task?.state
        switch true {
        case s.status == "offline":
            self.init(3, "offline", Color(white: 0.75))
        case s.status == "waiting":
            self.init(0, "wartet auf dich", .red, why: s.waitingFor ?? "Eingabe nötig")
        case s.status == "busy":
            self.init(1, "arbeitet", .green)
        case state == "blocked":
            self.init(0, "blockiert", .orange, why: "Blockiert – braucht eine Entscheidung")
        case state == "waiting":
            self.init(2, "wartet auf Rückmeldung", .purple)
        case s.status == "shell":
            self.init(2, "Shell", .blue)
        default:
            self.init(2, "bereit", Color(white: 0.6))
        }
    }

    private init(_ rank: Int, _ label: String, _ color: Color, why: String? = nil) {
        self.rank = rank
        self.label = label
        self.color = color
        self.why = why
    }
}

@MainActor
final class StateStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var error: String?
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
        } catch {
            self.error = "hive nicht erreichbar (\(hiveURL.absoluteString)): \(error.localizedDescription)"
        }
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
