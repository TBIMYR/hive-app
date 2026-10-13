import Foundation

/// "Sleep when done": armed once, puts the Mac to sleep as soon as no session works any more. Before
/// that a grace period runs, which Mika can cancel and which ends by itself when a session starts
/// working again (a PM handing out the next task). Sleeping or cancelling disarms it.
public struct SleepWhenDone: Equatable {
    public static let grace: TimeInterval = 60

    public private(set) var armed = false
    /// End of the running grace period, nil while sessions still work
    public private(set) var deadline: Date?

    public init() {}

    public mutating func arm() { armed = true }

    public mutating func cancel() {
        armed = false
        deadline = nil
    }

    /// Called on every refresh with the number of working sessions. true = put the Mac to sleep now.
    public mutating func update(working: Int, now: Date) -> Bool {
        guard armed else { return false }
        guard working == 0 else {
            deadline = nil
            return false
        }
        guard let deadline else {
            deadline = now.addingTimeInterval(Self.grace)
            return false
        }
        guard now >= deadline else { return false }
        cancel()
        return true
    }
}
