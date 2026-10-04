import Foundation
import Testing
@testable import HiveCore

private func spawn(_ script: String) throws -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", script]
    try p.run()
    return p
}

@Test func startTimeOfOwnProcessAndMissingPid() {
    #expect(ProcessControl.startTime(Int(getpid())) != nil)
    #expect(ProcessControl.startTime(0) == nil)
    #expect(ProcessControl.startTime(99_999_999) == nil)
}

@Test func forceQuitEndsProcess() async throws {
    let p = try spawn("exec sleep 60")
    let pid = Int(p.processIdentifier)
    let started = try #require(ProcessControl.startTime(pid))
    #expect(await ProcessControl.forceQuit(pid: pid, started: started) == nil)
    p.waitUntilExit()
    #expect(p.terminationReason == .uncaughtSignal)
    #expect(p.terminationStatus == SIGTERM)
}

@Test func forceQuitKillsProcessIgnoringTerm() async throws {
    let p = try spawn("trap '' TERM; while :; do sleep 0.05; done")
    let pid = Int(p.processIdentifier)
    try await Task.sleep(nanoseconds: 200_000_000)  // until the trap is set
    let started = try #require(ProcessControl.startTime(pid))
    #expect(await ProcessControl.forceQuit(pid: pid, started: started, grace: 0.3) == nil)
    p.waitUntilExit()
    #expect(p.terminationStatus == SIGKILL)
}

@Test func forceQuitRefusesReusedPid() async throws {
    let p = try spawn("exec sleep 60")
    defer { p.terminate() }
    let pid = Int(p.processIdentifier)
    let other = Date(timeIntervalSince1970: 1)
    #expect(await ProcessControl.forceQuit(pid: pid, started: other) == "PID \(pid) now belongs to another process")
    #expect(p.isRunning)
}

@Test func forceQuitRefusesOwnProcess() async {
    let me = Int(getpid())
    #expect(await ProcessControl.forceQuit(pid: me, started: Date()) == "Refusing to end PID \(me)")
}
