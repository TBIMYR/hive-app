import Foundation

/// Inhalt des Kastens „Now“ in der Karte: was die Session gerade tut, was sie von dir will oder was zuletzt herauskam.
public struct NowLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// arbeitet: letzter Arbeitsschritt
        case working
        /// braucht dich: Freigabe eines Werkzeugs
        case permission
        /// braucht dich: Frage im letzten Satz (Antwort über das Antwortfeld)
        case question
        /// braucht dich: offene AskUserQuestion mit Optionen (Antwort im Terminal)
        case choice
        /// bereit oder offline: letzter Satz
        case done
    }

    public let kind: Kind
    public let text: String
    /// Befehl oder Pfad (klein darunter)
    public let detail: String?
    /// seit wann der Arbeitsschritt läuft (nur .working)
    public let at: String?
    /// Optionen einer offenen AskUserQuestion (nur .choice)
    public let options: [String]

    public init(kind: Kind, text: String, detail: String?, at: String?, options: [String] = []) {
        self.kind = kind
        self.text = text
        self.detail = detail
        self.at = at
        self.options = options
    }

    /// `rank` aus SessionStatus (0 braucht dich, 1 arbeitet, sonst bereit/offline). nil = kein Kasten.
    public init?(_ s: Session, rank: Int) {
        let action = s.lastAction
        switch rank {
        case 1:
            guard let action else { return nil }
            self.init(kind: .working, text: action.text, detail: action.detail, at: action.at)
        case 0:
            if let action, action.pending, action.tool == "AskUserQuestion" {
                self.init(kind: .choice, text: action.text, detail: nil, at: nil, options: action.options ?? [])
            } else if action?.pending == true || s.waitsForPermission {
                self.init(kind: .permission, text: action.map { "Allow \($0.tool)?" } ?? "Allow tool?",
                          detail: action?.detail, at: nil)
            } else if let q = s.lastSentence {
                self.init(kind: .question, text: q, detail: nil, at: nil)
            } else {
                return nil
            }
        default:
            guard let done = s.lastSentence else { return nil }
            self.init(kind: .done, text: done, detail: nil, at: nil)
        }
    }
}

extension Session {
    /// waitingFor sieht nach einer Freigabe aus („Permission prompt“ …)
    public var waitsForPermission: Bool { waitingFor?.localizedCaseInsensitiveContains("permission") == true }

    /// Antwortfeld zeigen: kein Werkzeugaufruf offen (sonst steht ein Auswahl-Dialog im Terminal, getippter
    /// Text landete falsch) und keine Freigabe.
    public var acceptsReply: Bool { lastAction?.pending != true && !waitsForPermission }

    /// Ab wann eine Aufgaben-Zeile als veraltet gilt: so viel älter als die letzte Aktivität.
    public static let taskOutdatedAfter: TimeInterval = 2 * 60 * 60

    /// Aufgaben-Zeile deutlich älter als die letzte Aktivität (letzter Arbeitsschritt oder Statuswechsel).
    public var taskOutdated: Bool {
        guard let updated = task?.updatedAt.flatMap(parseISO) else { return false }
        let activity = [lastAction?.at, statusUpdatedAt].compactMap { $0.flatMap(parseISO) }.max()
        guard let activity else { return false }
        return activity.timeIntervalSince(updated) > Self.taskOutdatedAfter
    }
}
