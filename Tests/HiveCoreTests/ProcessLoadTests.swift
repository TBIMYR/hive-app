import Foundation
import Testing
@testable import HiveCore

@Test func parsesPsLinesWithEitherDecimalSign() {
    let rows = ProcessLoad.parse("  100     1   0.5\n  101   100 141,1\nbroken line\n\n")
    #expect(rows == [.init(pid: 100, ppid: 1, cpu: 0.5), .init(pid: 101, ppid: 100, cpu: 141.1)])
}

@Test func sumsTheWholeProcessTreeOfASession() {
    let rows: [ProcessLoad.Row] = [
        .init(pid: 100, ppid: 1, cpu: 1),      // session
        .init(pid: 110, ppid: 100, cpu: 2),    // its shell
        .init(pid: 111, ppid: 110, cpu: 140),  // test worker
        .init(pid: 112, ppid: 110, cpu: 95),   // test worker
        .init(pid: 200, ppid: 1, cpu: 30),     // another session
        .init(pid: 300, ppid: 1, cpu: 80),     // unrelated
    ]
    let load = ProcessLoad.perRoot(rows, roots: [100, 200, 999])
    #expect(load == [100: 238, 200: 30])
}

@Test func aSessionBelowAnotherIsNotCountedTwice() {
    let rows: [ProcessLoad.Row] = [
        .init(pid: 100, ppid: 1, cpu: 10),
        .init(pid: 150, ppid: 100, cpu: 20),
        .init(pid: 151, ppid: 150, cpu: 300),
    ]
    #expect(ProcessLoad.perRoot(rows, roots: [100, 150]) == [100: 10, 150: 320])
}

@Test func showsLoadAsShareOfTheMacOnlyWhenNoticeable() {
    #expect(ProcessLoad.share(60, cores: 14) == nil)
    #expect(ProcessLoad.share(70, cores: 14) == 5)
    #expect(ProcessLoad.share(400, cores: 14) == 29)
    #expect(ProcessLoad.share(400, cores: 4) == 100)
    #expect(ProcessLoad.share(900, cores: 8) == 100)
    #expect(ProcessLoad.coresText(300) == "3")
    #expect(ProcessLoad.coresText(240) == "2.4")
}

@Test func samplesTheRunningTestProcess() {
    let me = Int(ProcessInfo.processInfo.processIdentifier)
    #expect(ProcessLoad.sample(roots: [me])[me] != nil)
    #expect(ProcessLoad.sample(roots: []).isEmpty)
}
