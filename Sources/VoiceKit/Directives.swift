import Foundation

/// What the model asks the app to do, written as a marker line at the end of its answer:
/// `[[send lu.01: text]]` proposes a message, `[[confirm]]` sends the proposal, `[[cancel]]` drops it,
/// `[[reply lu.01: text]]` sends a short, clear message right away (after a short pause for "stop").
public enum Directive: Equatable, Sendable {
    case propose(to: String, text: String)
    case reply(to: String, text: String)
    case confirm
    case cancel
}

public enum Directives {
    /// Splits a complete answer into the part to speak and the markers.
    public static func parse(_ answer: String) -> (spoken: String, directives: [Directive]) {
        var spoken = ""
        var found: [Directive] = []
        var rest = Substring(answer)
        while let open = rest.range(of: "[[") {
            spoken += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "]]") else { rest = ""; break }
            if let d = directive(String(rest[open.upperBound..<close.lowerBound])) { found.append(d) }
            rest = rest[close.upperBound...]
        }
        spoken += rest
        return (spoken.trimmingCharacters(in: .whitespacesAndNewlines), found)
    }

    static func directive(_ body: String) -> Directive? {
        let b = body.trimmingCharacters(in: .whitespaces)
        switch b.lowercased() {
        case "confirm": return .confirm
        case "cancel": return .cancel
        default: break
        }
        let verb = b.prefix(while: { $0 != " " }).lowercased()
        guard verb == "send" || verb == "reply", let colon = b.firstIndex(of: ":") else { return nil }
        let to = b[b.index(b.startIndex, offsetBy: verb.count)..<colon].trimmingCharacters(in: .whitespaces)
        let text = b[b.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !to.isEmpty, !text.isEmpty else { return nil }
        return verb == "send" ? .propose(to: to, text: text) : .reply(to: to, text: text)
    }
}

/// Streams the spoken part only: everything from the first "[[" on is held back,
/// so a marker is never read out while the answer is still coming in.
public struct SpokenFilter {
    private var pending = ""
    private var inMarker = false

    public init() {}

    public mutating func feed(_ text: String) -> String {
        guard !inMarker else { return "" }
        pending += text
        if let r = pending.range(of: "[[") {
            inMarker = true
            defer { pending = "" }
            return String(pending[..<r.lowerBound])
        }
        // a single "[" at the end could still become "[["
        if pending.hasSuffix("[") {
            let out = String(pending.dropLast())
            pending = "["
            return out
        }
        defer { pending = "" }
        return pending
    }

    public mutating func finish() -> String {
        defer { pending = "" }
        return inMarker ? "" : pending
    }
}

/// The confirmation gate: a message only goes out if it was proposed in an earlier answer
/// (and was therefore read out to the user) and a later answer confirms it. The exception is a short, clear message
/// to a reachable session: it goes out after a pause in which the user can still stop it.
public struct Handoff: Equatable, Sendable {
    public struct Message: Equatable, Sendable {
        public let to: String
        public let text: String
    }

    public enum Action: Equatable, Sendable {
        case send(Message)
        /// send after the countdown unless the user stops it
        case countdown(Message)
    }

    /// longer replies are real tasks: those need a proper yes
    public static let quickReplyLimit = 160

    public private(set) var pending: Message?

    public init() {}

    /// Applies the markers of one answer; `reachable` are the sessions a message can be typed into right now.
    public mutating func apply(_ directives: [Directive], reachable: Set<String> = []) -> Action? {
        let before = pending
        var send: Action?
        for d in directives {
            switch d {
            case let .reply(to, text):
                let m = Message(to: to, text: text)
                if reachable.contains(to), text.count <= Self.quickReplyLimit { send = .countdown(m); pending = nil } else { pending = m }
            case let .propose(to, text): pending = Message(to: to, text: text)
            case .cancel: pending = nil
            case .confirm:
                // a confirm in the same answer as its proposal does not count: the user never heard it
                if let p = before, pending == p { send = .send(p); pending = nil }
            }
        }
        return send
    }
}
