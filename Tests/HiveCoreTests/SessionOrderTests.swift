import Testing
@testable import HiveCore

/// Session with status from the register; `at` = statusUpdatedAt
private func s(_ name: String, _ status: String = "idle", group: String = "al", isPm: Bool = false,
               at: String? = nil, taskState: String? = nil) -> Session {
    Session(name: name, group: group, isPm: isPm, pid: 1, alive: status != "offline", status: status,
            statusUpdatedAt: at,
            task: taskState.map { Session.TaskLine(text: "x", state: $0, updatedAt: nil, stale: false) })
}

private func order(_ items: [Session], labels: [String: String] = [:]) -> [String] {
    SessionOrder.sorted(items, session: { $0 }, status: { SessionStatus($0) }, labels: labels).map(\.name)
}

@Test func groupKeyWithoutGroupIsTheName() {
    #expect(Session(name: "keeper", group: "").groupKey == "keeper")
    #expect(Session(name: "al.01", group: "al").groupKey == "al")
}

@Test func sortsByRank() {
    let items = [s("a", "offline"), s("b"), s("c", "busy"), s("d", "waiting")]
    #expect(order(items) == ["d", "c", "b", "a"])
}

@Test func rankZeroSortedByWaitTime() {
    let items = [s("a", "waiting", at: "2026-10-03T10:05:00Z"), s("b", "waiting", at: "2026-10-03T10:00:00Z")]
    #expect(order(items) == ["b", "a"])
}

@Test func rankZeroWithoutTimeComesFirst() {
    let items = [s("a", "waiting", at: "2026-10-03T10:00:00Z"), s("b", "waiting")]
    #expect(order(items) == ["b", "a"])
}

@Test func rankZeroSameTimeSortedByName() {
    let t = "2026-10-03T10:00:00Z"
    #expect(order([s("b", "waiting", at: t), s("a", "waiting", at: t)]) == ["a", "b"])
    #expect(order([s("b", "waiting"), s("a", "waiting")]) == ["a", "b"])
}

@Test func otherRanksMostRecentActivityFirst() {
    let items = [s("a", at: "2026-10-03T10:00:00Z"), s("b", at: "2026-10-03T11:00:00Z"), s("c")]
    #expect(order(items) == ["b", "a", "c"])
}

@Test func activityCountsTheLastWorkStep() {
    let a = Session(name: "a", group: "al", pid: 1, alive: true, status: "busy", statusUpdatedAt: "2026-10-03T10:00:00Z",
                    lastAction: WorkAction(tool: "Edit", text: "Editing", detail: nil, at: "2026-10-03T12:00:00Z", pending: false))
    let b = s("b", "busy", at: "2026-10-03T11:00:00Z")
    #expect(order([b, a]) == ["a", "b"])
}

@Test func activityBeatsProjectAndPm() {
    let items = [s("al.pm", group: "al", isPm: true, at: "2026-10-03T10:00:00Z"),
                 s("zz.01", group: "zz", at: "2026-10-03T11:00:00Z")]
    #expect(order(items, labels: ["al": "alpha", "zz": "zeta"]) == ["zz.01", "al.pm"])
}

@Test func sameActivitySortedByName() {
    #expect(order([s("al.02"), s("al.01")]) == ["al.01", "al.02"])
}
