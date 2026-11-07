import Foundation

/// The broadcast field: one typed message, possibly for several sessions. Unlike the voice it does not wait for a
/// spoken yes in a later turn; the user confirms with a button, so a proposal only needs to be collected.
public enum Broadcast {
    public struct Plan: Equatable, Sendable {
        /// clear, short messages to reachable sessions: out at once
        public var now: [Handoff.Message] = []
        /// the rest: the user confirms them first
        public var ask: [Handoff.Message] = []
        /// offline sessions to start again with their handover, at once
        public var wake: [Wake] = []
    }

    public struct Wake: Equatable, Sendable {
        public var name: String
        /// a short, clear message for it becomes its first prompt
        public var task: String?

        public init(name: String, task: String? = nil) { self.name = name; self.task = task }
    }

    /// Same rule as the voice: a reply goes out at once only if the session can be typed into and the text is short;
    /// proposals always ask. One message per session, the last marker wins. A session that is already
    /// reachable is not woken; a short reply to a woken one is its first prompt.
    public static func plan(_ directives: [Directive], reachable: Set<String>) -> Plan {
        var plan = Plan()
        for case let .wake(name) in directives where !reachable.contains(name) && !plan.wake.contains(where: { $0.name == name }) {
            plan.wake.append(Wake(name: name))
        }
        for d in directives {
            let m: Handoff.Message, quick: Bool
            switch d {
            case let .reply(to, text):
                m = Handoff.Message(to: to, text: text)
                quick = text.count <= Handoff.quickReplyLimit
                    && (reachable.contains(to) || plan.wake.contains { $0.name == to })
            case let .propose(to, text):
                m = Handoff.Message(to: to, text: text)
                quick = false
            case .wake, .confirm, .cancel: continue
            }
            plan.now.removeAll { $0.to == m.to }
            plan.ask.removeAll { $0.to == m.to }
            if let i = plan.wake.firstIndex(where: { $0.name == m.to }) { plan.wake[i].task = nil }
            if quick, let i = plan.wake.firstIndex(where: { $0.name == m.to }) {
                plan.wake[i].task = m.text
            } else if quick {
                plan.now.append(m)
            } else {
                plan.ask.append(m)
            }
        }
        return plan
    }
}
