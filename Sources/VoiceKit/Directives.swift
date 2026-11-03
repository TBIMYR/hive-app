import Foundation

/// What the model asks the app to do, written as a marker line at the end of its answer:
/// `[[send lu.01: text]]` proposes a message, `[[confirm]]` sends the proposal, `[[cancel]]` drops it.
public enum Directive: Equatable, Sendable {
    case propose(to: String, text: String)
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
        guard b.lowercased().hasPrefix("send "), let colon = b.firstIndex(of: ":") else { return nil }
        let to = b[b.index(b.startIndex, offsetBy: 5)..<colon].trimmingCharacters(in: .whitespaces)
        let text = b[b.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !to.isEmpty, !text.isEmpty else { return nil }
        return .propose(to: to, text: text)
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
/// (and was therefore read out to the user) and a later answer confirms it.
public struct Handoff: Equatable, Sendable {
    public struct Message: Equatable, Sendable {
        public let to: String
        public let text: String
    }

    public private(set) var pending: Message?

    public init() {}

    /// Applies the markers of one answer; returns the message to send now, if any.
    public mutating func apply(_ directives: [Directive]) -> Message? {
        let before = pending
        var send: Message?
        for d in directives {
            switch d {
            case let .propose(to, text): pending = Message(to: to, text: text)
            case .cancel: pending = nil
            case .confirm:
                // a confirm in the same answer as its proposal does not count: the user never heard it
                if let p = before, pending == p { send = p; pending = nil }
            }
        }
        return send
    }
}
