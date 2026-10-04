import Testing
@testable import HiveCore

private func live(_ name: String, pid: Int, pane: String?) -> Session {
    Session(name: name, group: "al", pid: pid, tmuxPane: pane, alive: true, status: "idle")
}
private func offline(_ name: String) -> Session { Session(name: name, group: "al", hasHandover: true) }

@Test func tmuxMatchesViaPaneEvenAfterRename() {
    // via /rename al.01 became al.neu; tmux still calls it al.01, and the old al.01 handover still exists
    let s = [live("al.neu", pid: 1, pane: "%3"), offline("al.01")]
    let m = TmuxMatch.resolve(s, tmuxSessions: ["al.01"], sessionOfPane: ["%3": "al.01"])
    #expect(m[s[0].id] == "al.01")
    #expect(m[s[1].id] == nil)
}

@Test func tmuxMatchesViaNameWithoutPane() {
    // shell in tmux without Claude, or a register entry without a tmux field
    let s = [offline("al.02"), live("al.03", pid: 2, pane: nil)]
    let m = TmuxMatch.resolve(s, tmuxSessions: ["al.02", "al.03"], sessionOfPane: ["%1": "al.02", "%2": "al.03"])
    #expect(m[s[0].id] == "al.02")
    #expect(m[s[1].id] == "al.03")
}

@Test func paneFromDifferentServerDoesNotCount() {
    // pane ID from a different tmux server that doesn't exist in the hive server
    let s = [live("al.04", pid: 3, pane: "%9")]
    #expect(TmuxMatch.resolve(s, tmuxSessions: [], sessionOfPane: ["%1": "x"]).isEmpty)
}
