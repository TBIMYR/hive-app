import Testing
@testable import HiveCore

@Test func phonePushWaitsUntilAway() {
    var p = PhonePush()
    #expect(p.update(added: ["lu.01": "Permission"], removed: [], away: false).isEmpty)
    // still open when Mika leaves: pushed once, then not again
    #expect(p.update(added: [:], removed: [], away: true) == ["lu.01": "Permission"])
    #expect(p.update(added: [:], removed: [], away: true).isEmpty)
}

@Test func phonePushSendsNewNeedsWhileAway() {
    var p = PhonePush()
    #expect(p.update(added: ["or.pm": "Question"], removed: [], away: true) == ["or.pm": "Question"])
}

@Test func phonePushForgetsResolvedNeeds() {
    var p = PhonePush()
    _ = p.update(added: ["lu.01": "Permission"], removed: [], away: true)
    // resolved before the next push: neither it nor a later return of the old need is lost
    #expect(p.update(added: [:], removed: ["lu.01"], away: true).isEmpty)
    #expect(p.update(added: ["lu.01": "Question"], removed: [], away: true) == ["lu.01": "Question"])
}

@Test func phonePushDropsNeedsResolvedWhilePresent() {
    var p = PhonePush()
    _ = p.update(added: ["lu.01": "Permission"], removed: [], away: false)
    #expect(p.update(added: [:], removed: ["lu.01"], away: true).isEmpty)
}
