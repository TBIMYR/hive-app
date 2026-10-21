import Testing
@testable import HiveCore

private func status(_ status: String, background: Int = 0) -> SessionStatus {
    SessionStatus(Session(name: "lu.01", group: "lu", pid: 1, alive: true, status: status, backgroundTasks: background))
}

@Test func keepAwakeOnlyWhileWorking() {
    #expect(KeepAwake.reason(mode: .whileWorking, statuses: [status("idle"), status("busy")]) == "Hive: 1 session is working")
    #expect(KeepAwake.reason(mode: .whileWorking, statuses: [status("busy"), status("idle", background: 2)])
            == "Hive: 2 sessions are working")
    #expect(KeepAwake.reason(mode: .whileWorking, statuses: [status("idle"), status("waiting")]) == nil)
    #expect(KeepAwake.reason(mode: .off, statuses: [status("busy")]) == nil)
}

@Test func keepAwakeAlwaysHoldsWithoutWork() {
    #expect(KeepAwake.reason(mode: .always, statuses: []) == "Hive: keep awake")
    #expect(KeepAwake.reason(mode: .always, statuses: [status("busy")]) == "Hive: keep awake")
}

@Test func keepAwakeSwitchCyclesThroughAllModes() {
    #expect(KeepAwake.Mode.whileWorking.next == .always)
    #expect(KeepAwake.Mode.always.next == .off)
    #expect(KeepAwake.Mode.off.next == .whileWorking)
}
