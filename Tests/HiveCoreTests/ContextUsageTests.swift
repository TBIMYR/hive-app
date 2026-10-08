import Foundation
import Testing
@testable import HiveCore

@Test func readsContextPercentPerSession() throws {
    let home = NSTemporaryDirectory() + "ctx-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: home) }
    try FileManager.default.createDirectory(atPath: "\(home)/hive/context", withIntermediateDirectories: true)
    try #"{"used_percentage":37,"written_at":1}"#.write(toFile: "\(home)/hive/context/abc-1.json", atomically: true, encoding: .utf8)
    try #"{"used_percentage":140}"#.write(toFile: "\(home)/hive/context/big.json", atomically: true, encoding: .utf8)
    #expect(ContextUsage.percent(claudeHome: home, sessionId: "abc-1") == 37)
    #expect(ContextUsage.percent(claudeHome: home, sessionId: "big") == 100)
    #expect(ContextUsage.percent(claudeHome: home, sessionId: "missing") == nil)
    #expect(ContextUsage.percent(claudeHome: home, sessionId: "../x") == nil)
}
