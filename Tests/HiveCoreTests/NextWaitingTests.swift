import Testing
@testable import HiveCore

private let waiting = ["lu.01", "lu.03", "keeper"]

@Test func waitingSelectionWithoutFocusStays() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "lu.03", terminalFocused: false) == "lu.03")
}

@Test func waitingSelectionWithFocusMovesOn() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "lu.01", terminalFocused: true) == "lu.03")
}

@Test func atTheEndWrapsToTheFirst() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "keeper", terminalFocused: true) == "lu.01")
}

@Test func nonWaitingSelectionJumpsToTheFirst() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "fj.01", terminalFocused: true) == "lu.01")
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "fj.01", terminalFocused: false) == "lu.01")
}

@Test func withoutSelectionTheFirst() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: nil, terminalFocused: false) == "lu.01")
}

@Test func withoutCandidatesSelectionStays() {
    #expect(SessionOrder.nextWaiting(candidates: [], selected: "fj.01", terminalFocused: true) == "fj.01")
    #expect(SessionOrder.nextWaiting(candidates: [], selected: nil, terminalFocused: false) == nil)
}
