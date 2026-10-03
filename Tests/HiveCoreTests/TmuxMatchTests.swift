import Testing
@testable import HiveCore

private func live(_ name: String, pid: Int, pane: String?) -> Session {
    Session(name: name, group: "al", pid: pid, tmuxPane: pane, alive: true, status: "idle")
}
private func offline(_ name: String) -> Session { Session(name: name, group: "al", hasHandover: true) }

@Test func tmuxUeberPaneAuchNachUmbenennen() {
    // per /rename aus al.01 wurde al.neu, tmux heißt weiter al.01; das alte Handover al.01 liegt noch da
    let s = [live("al.neu", pid: 1, pane: "%3"), offline("al.01")]
    let m = TmuxMatch.resolve(s, tmuxSessions: ["al.01"], sessionOfPane: ["%3": "al.01"])
    #expect(m[s[0].id] == "al.01")
    #expect(m[s[1].id] == nil)
}

@Test func tmuxUeberNamenOhnePane() {
    // Shell in tmux ohne Claude oder Register-Eintrag ohne Feld tmux
    let s = [offline("al.02"), live("al.03", pid: 2, pane: nil)]
    let m = TmuxMatch.resolve(s, tmuxSessions: ["al.02", "al.03"], sessionOfPane: ["%1": "al.02", "%2": "al.03"])
    #expect(m[s[0].id] == "al.02")
    #expect(m[s[1].id] == "al.03")
}

@Test func paneAusAnderemServerZaehltNicht() {
    // Pane-ID aus einem anderen tmux-Server, die es im hive-Server nicht gibt
    let s = [live("al.04", pid: 3, pane: "%9")]
    #expect(TmuxMatch.resolve(s, tmuxSessions: [], sessionOfPane: ["%1": "x"]).isEmpty)
}
