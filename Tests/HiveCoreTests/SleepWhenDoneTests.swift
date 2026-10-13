import Foundation
import Testing
@testable import HiveCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

/// `#expect` can't call mutating members, so the value sits in a box.
private final class Box {
    var value = SleepWhenDone()
    var armed: Bool { value.armed }
    var deadline: Date? { value.deadline }
    func arm() { value.arm() }
    func cancel() { value.cancel() }
    func update(working: Int, now: Date) -> Bool { value.update(working: working, now: now) }
}

@Test func sleepWhenDoneWaitsForTheGracePeriod() {
    let s = Box()
    #expect(!s.update(working: 0, now: t0))
    #expect(s.deadline == nil)

    s.arm()
    #expect(!s.update(working: 2, now: t0))
    #expect(s.deadline == nil)
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(10)))
    #expect(s.deadline == t0.addingTimeInterval(10 + SleepWhenDone.grace))
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(60)))
    #expect(s.update(working: 0, now: t0.addingTimeInterval(70)))
    // one-shot: off again after sleeping
    #expect(!s.armed)
    #expect(s.deadline == nil)
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(200)))
}

@Test func sleepWhenDoneStartsOverWhenWorkResumes() {
    let s = Box()
    s.arm()
    #expect(!s.update(working: 0, now: t0))
    #expect(!s.update(working: 1, now: t0.addingTimeInterval(30)))
    #expect(s.armed)
    #expect(s.deadline == nil)
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(100)))
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(150)))
    #expect(s.update(working: 0, now: t0.addingTimeInterval(160)))
}

@Test func sleepWhenDoneCancelDisarms() {
    let s = Box()
    s.arm()
    #expect(!s.update(working: 0, now: t0))
    s.cancel()
    #expect(!s.armed)
    #expect(!s.update(working: 0, now: t0.addingTimeInterval(120)))
}
