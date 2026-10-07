import Foundation

/// Last activity per session name, frozen for a while so the overview doesn't reshuffle on every work
/// step. Sessions that are new since the last snapshot are added right away; the rest is retaken only
/// after `every` seconds.
public struct ActivitySnapshot: Equatable, Sendable {
    public private(set) var times: [String: Date] = [:]
    public private(set) var takenAt: Date = .distantPast

    public init() {}

    public mutating func update(_ sessions: [Session], now: Date, every: TimeInterval) {
        if now.timeIntervalSince(takenAt) >= every {
            times = Dictionary(sessions.compactMap { s in s.lastActivity.map { (s.name, $0) } }, uniquingKeysWith: max)
            takenAt = now
            return
        }
        for s in sessions where times[s.name] == nil {
            if let t = s.lastActivity { times[s.name] = t }
        }
    }
}
