import Testing
@testable import HiveCore

@Test func unbekannterProzessHatKeinTerminal() {
    #expect(Focus.tty(of: 999_999) == nil)
    #expect(Focus.focus(pid: 999_999) == "Session hat kein Terminal")
}

@Test func shellLiefertAusgabeUndStatus() {
    let r = Shell.run("/bin/echo", ["hallo"])
    #expect(r.status == 0)
    #expect(r.out == "hallo\n")
    #expect(Shell.run("/nonexistent", []).status == -1)
}
