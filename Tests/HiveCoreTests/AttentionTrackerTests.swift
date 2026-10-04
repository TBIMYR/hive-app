import Foundation
import Testing
@testable import HiveCore

private typealias Need = AttentionTracker.Need
private let t0 = Date(timeIntervalSince1970: 1000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func firstCallReportsNothing() {
    var t = AttentionTracker()
    let r = t.update(["al.01": Need(reason: "x")], now: t0)
    #expect(r.added.isEmpty && r.removed.isEmpty)
}

@Test func newThenGone() {
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    let r1 = t.update(["al.01": Need(reason: "Freigabe")], now: at(2))
    #expect(r1.added == ["al.01": "Freigabe"] && r1.removed.isEmpty)
    let r2 = t.update(["al.01": Need(reason: "Freigabe")], now: at(4))
    #expect(r2.added.isEmpty)
    let r3 = t.update([:], now: at(6))
    #expect(r3.removed == ["al.01"])
}

@Test func reportedAtStartAlsoDisappear() {
    var t = AttentionTracker()
    _ = t.update(["al.01": Need(reason: "x")], now: t0)
    #expect(t.update([:], now: at(2)).removed == ["al.01"])
}

@Test func newAgainAfterPause() {
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    _ = t.update(["al.01": Need(reason: "a")], now: at(2))
    _ = t.update([:], now: at(4))
    #expect(t.update(["al.01": Need(reason: "b")], now: at(6)).added == ["al.01": "b"])
}

@Test func reasonChangeWithoutNewNotification() {
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    _ = t.update(["al.01": Need(reason: "a")], now: at(2))
    let r = t.update(["al.01": Need(reason: "b")], now: at(4))
    #expect(r.added.isEmpty && r.removed.isEmpty)
}

@Test func startOnlyAfterConfirmation() {
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    let start = Need(reason: "Start-Abfrage", confirmAfter: 3)
    #expect(t.update(["al.02": start], now: at(2)).added.isEmpty)
    #expect(t.update(["al.02": start], now: at(4)).added.isEmpty)   // 2 s < 3 s
    #expect(t.update(["al.02": start], now: at(6)).added == ["al.02": "Start-Abfrage"])
}

@Test func startDisappearsBeforeConfirmationSilently() {
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    _ = t.update(["al.02": Need(reason: "Start", confirmAfter: 3)], now: at(2))
    let r = t.update([:], now: at(4))
    #expect(r.added.isEmpty && r.removed.isEmpty)
}

@Test func switchFromStartToWaitingImmediately() {
    // the clock starts running at the first rank 0; "waiting for you" has no confirmation time
    var t = AttentionTracker()
    _ = t.update([:], now: t0)
    _ = t.update(["al.02": Need(reason: "Start", confirmAfter: 3)], now: at(2))
    #expect(t.update(["al.02": Need(reason: "Freigabe")], now: at(3)).added == ["al.02": "Freigabe"])
}
