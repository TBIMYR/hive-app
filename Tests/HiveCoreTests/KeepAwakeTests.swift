import Testing
@testable import HiveCore

private func status(_ status: String, background: Int = 0) -> SessionStatus {
    SessionStatus(Session(name: "lu.01", group: "lu", pid: 1, alive: true, status: status, backgroundTasks: background))
}

@Test func keepAwakeOnlyWhileWorking() {
    #expect(KeepAwake.reason(enabled: true, statuses: [status("idle"), status("busy")]) == "Hive: 1 session is working")
    #expect(KeepAwake.reason(enabled: true, statuses: [status("busy"), status("idle", background: 2)])
            == "Hive: 2 sessions are working")
    #expect(KeepAwake.reason(enabled: true, statuses: [status("idle"), status("waiting")]) == nil)
    #expect(KeepAwake.reason(enabled: false, statuses: [status("busy")]) == nil)
}
