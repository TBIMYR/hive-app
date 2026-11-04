import Foundation

/// The broadcast field: one typed message, possibly for several sessions. Unlike the voice it does not wait for a
/// spoken yes in a later turn; the user confirms with a button, so a proposal only needs to be collected.
public enum Broadcast {
    public struct Plan: Equatable, Sendable {
        /// clear, short messages to reachable sessions: out at once
        public var now: [Handoff.Message] = []
        /// the rest: the user confirms them first
        public var ask: [Handoff.Message] = []
    }

    /// Same rule as the voice: a reply goes out at once only if the session can be typed into and the text is short;
    /// proposals always ask. One message per session, the last marker wins.
    public static func plan(_ directives: [Directive], reachable: Set<String>) -> Plan {
        var plan = Plan()
        for d in directives {
            let m: Handoff.Message, quick: Bool
            switch d {
            case let .reply(to, text):
                m = Handoff.Message(to: to, text: text)
                quick = reachable.contains(to) && text.count <= Handoff.quickReplyLimit
            case let .propose(to, text):
                m = Handoff.Message(to: to, text: text)
                quick = false
            case .confirm, .cancel: continue
            }
            plan.now.removeAll { $0.to == m.to }
            plan.ask.removeAll { $0.to == m.to }
            if quick { plan.now.append(m) } else { plan.ask.append(m) }
        }
        return plan
    }
}
