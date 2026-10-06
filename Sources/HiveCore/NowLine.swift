import Foundation

/// Content of the "Now" box in the card: what the session is currently doing, what it wants from you, or what it last produced.
public struct NowLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// working: last work step
        case working
        /// needs you: approval of a tool
        case permission
        /// needs you: question in the last sentence (answer via the reply field)
        case question
        /// needs you: open AskUserQuestion with options (answer in the terminal)
        case choice
        /// ready or offline: last sentence
        case done
    }

    public let kind: Kind
    public let text: String
    /// Command or path (small, underneath)
    public let detail: String?
    /// since when the work step has been running (only .working)
    public let at: String?
    /// Options of an open AskUserQuestion (only .choice)
    public let options: [String]
    /// .choice with exactly one question without multi-select: answerable via button
    public let singleChoice: Bool

    public init(kind: Kind, text: String, detail: String?, at: String?, options: [String] = [], singleChoice: Bool = false) {
        self.kind = kind
        self.text = text
        self.detail = detail
        self.at = at
        self.options = options
        self.singleChoice = singleChoice
    }

    /// `rank` from SessionStatus (0 needs you, 1 working, otherwise ready/offline). nil = no box.
    public init?(_ s: Session, rank: Int) {
        let action = s.lastAction
        switch rank {
        case 1 where s.status != "busy" && s.backgroundTasks > 0:
            // only background tasks are running: the last work step would be stale, the last sentence says more
            guard let done = s.lastSentence else { return nil }
            self.init(kind: .done, text: done, detail: nil, at: nil)
        case 1:
            guard let action else { return nil }
            self.init(kind: .working, text: action.text, detail: action.detail, at: action.at)
        case 0:
            if let action, action.pending, action.tool == "AskUserQuestion" {
                let options = action.options ?? []
                self.init(kind: .choice, text: action.text, detail: nil, at: nil, options: options,
                          singleChoice: action.questionCount == 1 && action.multiSelect != true && !options.isEmpty)
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
    /// waitingFor looks like an approval ("Permission prompt" …)
    public var waitsForPermission: Bool { waitingFor?.localizedCaseInsensitiveContains("permission") == true }

    /// Show the reply field: no tool call pending (otherwise a choice dialog is showing in the terminal and
    /// typed text would land in the wrong place) and no approval pending.
    public var acceptsReply: Bool { lastAction?.pending != true && !waitsForPermission }

    /// When a task line counts as outdated: this much older than the last activity.
    public static let taskOutdatedAfter: TimeInterval = 2 * 60 * 60

    /// Task line noticeably older than the last activity (last work step or status change).
    public var taskOutdated: Bool {
        guard let updated = task?.updatedAt.flatMap(parseISO) else { return false }
        guard let activity = lastActivity else { return false }
        return activity.timeIntervalSince(updated) > Self.taskOutdatedAfter
    }
}
