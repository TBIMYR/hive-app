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

@Test func pendingReplyComesFirst() {
    let items = [s("a"), s("b", taskState: "waiting")]
    #expect(order(items) == ["b", "a"])
}

@Test func thenSortedByProjectName() {
    let items = [s("x.01", group: "x"), s("y.01", group: "y")]
    #expect(order(items, labels: ["x": "zeta", "y": "Alpha"]) == ["y.01", "x.01"])
}

@Test func pmComesBeforeWorker() {
    let items = [s("al.01"), s("al.pm", isPm: true)]
    #expect(order(items, labels: ["al": "alpha"]) == ["al.pm", "al.01"])
}

@Test func finallySortedByName() {
    #expect(order([s("al.02"), s("al.01")]) == ["al.01", "al.02"])
}
