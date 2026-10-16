import Foundation
import Testing
@testable import HiveCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func inc() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@Test func reportsChangesThrottled() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "hive-watch-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let count = Counter()
    let watcher = Watcher(paths: [dir.path], delay: 0.2) { count.inc() }
    try await Task.sleep(for: .milliseconds(300))   // let the stream start up
    let base = count.value   // FSEvents often still reports the creation of the folder
    for i in 0..<5 { try "x".write(to: dir.appending(path: "f\(i)"), atomically: false, encoding: .utf8) }
    try await Task.sleep(for: .milliseconds(1500))
    #expect(count.value - base >= 1)
    #expect(count.value - base <= 2, "five writes in quick succession trigger at most two events")
    withExtendedLifetime(watcher) {}
}
