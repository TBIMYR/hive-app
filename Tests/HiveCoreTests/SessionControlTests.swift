import Foundation
import Testing
@testable import HiveCore

@Test func targetMatchesSessionExactly() {
    // "lu.01" without "=…:" would be read by tmux as window 01 of session "lu"
    #expect(SessionControl.target("lu.01") == "=lu.01:")
}

@Test func typingSendsTextLiterallyThenEnter() {
    let cmds = SessionControl.typeArgs("-v; $HOME", into: "lu.01")
    #expect(cmds == [
        ["send-keys", "-t", "=lu.01:", "-l", "--", "-v; $HOME"],
        ["send-keys", "-t", "=lu.01:", "Enter"],
    ])
}

@Test func killAddressesExactSession() {
    #expect(SessionControl.killArgs("lu.01") == ["kill-session", "-t", "=lu.01:"])
}

@Test func replyWithoutTextIsNil() {
    #expect(SessionControl.replyText("   \n") == nil)
    #expect(SessionControl.replyText("  yes, go on \n") == "yes, go on")
}

@Test func claudeCommandWithName() {
    #expect(SessionControl.claudeCommand("lu.01") == "claude -n lu.01")
    // special characters are quoted for the shell
    #expect(SessionControl.claudeCommand("my name") == "claude -n 'my name'")
    #expect(SessionControl.claudeCommand("it's") == "claude -n 'it'\\''s'")
}

@Test func hasExitedWhenShellInFrontOrTmuxGone() {
    #expect(SessionControl.hasExited(wasAlive: true, aliveNow: true, paneCommand: "zsh"))
    #expect(SessionControl.hasExited(wasAlive: true, aliveNow: true, paneCommand: nil))
    #expect(!SessionControl.hasExited(wasAlive: true, aliveNow: true, paneCommand: "claude.exe"))
}

@Test func hasExitedWhenRegisterNoLongerAlive() {
    #expect(SessionControl.hasExited(wasAlive: true, aliveNow: false, paneCommand: "claude.exe"))
    // was never alive in the register (e.g. codex in tmux): the register says nothing, the pane decides
    #expect(!SessionControl.hasExited(wasAlive: false, aliveNow: false, paneCommand: "codex"))
}

@Test func warningsWhenClosing() {
    let busy = Session(name: "lu.01", group: "lu", pid: 1, alive: true, status: "busy", hasHandover: false)
    #expect(SessionControl.closeWarnings(busy) == ["It is still working", "It has no handover yet"])
    let calm = Session(name: "lu.02", group: "lu", pid: 2, alive: true, status: "idle", hasHandover: true)
    #expect(SessionControl.closeWarnings(calm).isEmpty)
}

@Test func waitUntilEndsAsSoonAsConditionIsMet() async {
    var n = 0
    let ok = await SessionControl.waitUntil(timeout: 2, interval: 0.01) { n += 1; return n >= 3 }
    #expect(ok)
    #expect(n == 3)
}

@Test func waitUntilGivesUpAfterTimeout() async {
    let start = Date()
    let ok = await SessionControl.waitUntil(timeout: 0.1, interval: 0.02) { false }
    #expect(!ok)
    #expect(Date().timeIntervalSince(start) < 1)
}

/// Against real tmux, on its own server `-L hive-test` (never `-L hive`).
@Test func addressingAgainstRealTmux() throws {
    guard let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
    func t(_ args: [String]) -> Shell.Result { Shell.run(tmux, ["-L", "hive-test", "-f", "/dev/null"] + args) }
    defer { _ = t(["kill-server"]) }
    for name in ["lu", "lu.01", "lu.011"] {
        #expect(t(["new-session", "-d", "-s", name, "-x", "80", "-y", "10", "cat"]).status == 0)
    }
    for args in SessionControl.typeArgs("-n hi", into: "lu.01") { #expect(t(args).status == 0) }
    Thread.sleep(forTimeInterval: 0.3)
    let pane = { (n: String) in t(["capture-pane", "-p", "-t", SessionControl.target(n)]).out }
    #expect(pane("lu.01").contains("-n hi"))
    #expect(!pane("lu.011").contains("hi"))
    #expect(!pane("lu").contains("hi"))
    // no prefix match: "lu.0" doesn't exist
    #expect(t(SessionControl.killArgs("lu.0")).status != 0)
    #expect(t(SessionControl.killArgs("lu.01")).status == 0)
    let left = t(["list-sessions", "-F", "#{session_name}"]).out.split(separator: "\n").map(String.init)
    #expect(left.sorted() == ["lu", "lu.011"])
}
