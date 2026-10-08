import Foundation
import Testing
@testable import HiveCore

@Test func findsExecutableOnPath() {
    #expect(LoginShell.findExecutable("sh", path: "/nonexistent:/bin") == "/bin/sh")
    #expect(LoginShell.findExecutable("no-such-tool-xyz", path: "/bin:/usr/bin") == nil)
}

@Test func longRunReadsBothPipesAndCwd() {
    let r = LongRun("/bin/sh", ["-c", "pwd; head -c 200000 /dev/zero | tr '\\0' x >&2; echo done"], cwd: "/tmp").run(timeout: 10)
    #expect(r.status == 0)
    #expect(r.out.contains("/tmp") && r.out.contains("done"))
    #expect(r.err.count == 200000)
}

@Test func longRunTimesOutWithChildren() {
    let start = Date()
    // sh forks sleep (not the last command), so the child holds the pipes
    let r = LongRun("/bin/sh", ["-c", "sleep 5; echo x"]).run(timeout: 0.3)
    #expect(r.timedOut && r.status != 0)
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func longRunCancels() async {
    let job = LongRun("/bin/sh", ["-c", "sleep 5; echo x"])
    let start = Date()
    Task.detached { try? await Task.sleep(nanoseconds: 300_000_000); job.cancel() }
    let r = await Task.detached { job.run(timeout: 10) }.value
    #expect(r.cancelled && !r.timedOut)
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func longRunPassesEnvironment() {
    let r = LongRun("/bin/sh", ["-c", "echo $HIVE_X"], env: ["HIVE_X": "42"]).run(timeout: 5)
    #expect(r.out.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
}
