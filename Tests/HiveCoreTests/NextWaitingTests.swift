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

@Test func startSelectionPrefersARunningFavoriteThenAWorkingSession() {
    typealias S = (name: String, rank: Int, favorite: Bool)
    let all: [S] = [("lu.01", 2, false), ("or.pm", 3, true), ("lu.02", 1, false), ("fj.pm", 2, true), ("ki.01", 1, true)]
    #expect(SessionOrder.initial(all) == "fj.pm")
    // no running favorite: the first working one
    #expect(SessionOrder.initial(Array(all.prefix(3))) == "lu.02")
    // nothing works: the first that runs
    #expect(SessionOrder.initial(Array(all.prefix(2))) == "lu.01")
    #expect(SessionOrder.initial([("or.pm", 3, true)]) == nil)
    #expect(SessionOrder.initial([]) == nil)
}
