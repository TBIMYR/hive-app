import Testing
@testable import HiveCore

private let waiting = ["lu.01", "lu.03", "keeper"]

@Test func wartendeAuswahlOhneFokusBleibt() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "lu.03", terminalFocused: false) == "lu.03")
}

@Test func wartendeAuswahlMitFokusGehtWeiter() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "lu.01", terminalFocused: true) == "lu.03")
}

@Test func amEndeWiederDieErste() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "keeper", terminalFocused: true) == "lu.01")
}

@Test func nichtWartendeAuswahlSpringtZurErsten() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "fj.01", terminalFocused: true) == "lu.01")
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: "fj.01", terminalFocused: false) == "lu.01")
}

@Test func ohneAuswahlDieErste() {
    #expect(SessionOrder.nextWaiting(candidates: waiting, selected: nil, terminalFocused: false) == "lu.01")
}

@Test func ohneKandidatinBleibtDieAuswahl() {
    #expect(SessionOrder.nextWaiting(candidates: [], selected: "fj.01", terminalFocused: true) == "fj.01")
    #expect(SessionOrder.nextWaiting(candidates: [], selected: nil, terminalFocused: false) == nil)
}
