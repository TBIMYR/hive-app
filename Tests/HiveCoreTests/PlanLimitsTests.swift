import Foundation
import Testing
@testable import HiveCore

private let statusLine = """
{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":1800003600},
 "seven_day":{"used_percentage":78.5,"resets_at":1800100000}},"written_at":1800000000.25}
"""

// fake values; the real file holds much more (account, OAuth), which must be ignored
private let claudeConfig = """
{"oauthAccount":{"emailAddress":"mika@example.com"},"numStartups":3,
 "cachedUsageUtilization":{"fetchedAtMs":1800000600000,"accountUuid":"00000000-0000-0000-0000-000000000000",
  "utilization":{
   "five_hour":{"utilization":21,"resets_at":"2027-01-15T09:00:00.600693+00:00"},
   "seven_day":{"utilization":80,"resets_at":"2027-01-16T10:00:00+00:00"},
   "seven_day_opus":null,
   "limits":[
    {"kind":"session","percent":21,"severity":"normal","resets_at":"2027-01-15T09:00:00.600693+00:00","scope":null,"is_active":false},
    {"kind":"weekly_all","percent":80,"severity":"warning","resets_at":"2027-01-16T10:00:00+00:00","scope":null,"is_active":true},
    {"kind":"weekly_scoped","percent":11,"severity":"normal","resets_at":"2027-01-16T10:00:00.600925+00:00",
     "scope":{"model":{"id":null,"display_name":"Lyra"},"surface":null},"is_active":false}]}}}
"""

private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

@Test func parsesStatusLineFile() throws {
    let l = try #require(PlanLimits.fromStatusLine(Data(statusLine.utf8)))
    #expect(l.source == .statusLine)
    #expect(l.fiveHour == .init(percent: 19, resetsAt: at(1800003600)))
    #expect(l.sevenDay == .init(percent: 78.5, resetsAt: at(1800100000)))
    #expect(l.fetchedAt == at(1800000000.25))
    #expect(l.scoped.isEmpty)
}

@Test func statusLineWithOneWindowOrNone() {
    let one = PlanLimits.fromStatusLine(Data(#"{"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1}},"written_at":1}"#.utf8))
    #expect(one?.fiveHour == nil)
    #expect(one?.sevenDay?.percent == 5)
    #expect(PlanLimits.fromStatusLine(Data(#"{"rate_limits":{},"written_at":1}"#.utf8)) == nil)
    #expect(PlanLimits.fromStatusLine(Data("not json".utf8)) == nil)
}

@Test func parsesOnlyTheCacheKeyOfClaudeConfig() throws {
    let l = try #require(PlanLimits.fromClaudeConfig(Data(claudeConfig.utf8)))
    #expect(l.source == .claudeCache)
    #expect(l.fetchedAt == at(1800000600))
    #expect(l.fiveHour?.percent == 21)
    // six decimal places as Claude Code writes them
    let reset = try #require(l.fiveHour?.resetsAt)
    #expect(abs(reset.timeIntervalSince(parseISO("2027-01-15T09:00:00Z")!)) < 1)
    #expect(l.sevenDay?.resetsAt == parseISO("2027-01-16T10:00:00Z"))
    #expect(l.scoped.map(\.name) == ["Lyra"])
    #expect(l.scoped.first?.window.percent == 11)
}

@Test func cacheFallsBackToLimitsList() throws {
    let json = """
    {"cachedUsageUtilization":{"fetchedAtMs":1000,"limits":[
     {"kind":"session","percent":40,"resets_at":"2027-01-15T09:00:00Z"},
     {"kind":"weekly_all","percent":60,"resets_at":"2027-01-16T10:00:00Z"}]}}
    """
    let l = try #require(PlanLimits.fromClaudeConfig(Data(json.utf8)))
    #expect(l.fiveHour?.percent == 40)
    #expect(l.sevenDay?.percent == 60)
    #expect(PlanLimits.fromClaudeConfig(Data(#"{"other":1}"#.utf8)) == nil)
}

@Test func expiredWindowsAreDropped() throws {
    let l = try #require(PlanLimits.fromStatusLine(Data(statusLine.utf8)))
    let mid = try #require(l.droppingExpired(now: at(1800050000)))
    #expect(mid.fiveHour == nil)
    #expect(mid.sevenDay != nil)
    #expect(l.droppingExpired(now: at(1800100000)) == nil)
}

@Test func newerSourceWins() throws {
    let line = try #require(PlanLimits.fromStatusLine(Data(statusLine.utf8)))   // written 1800000000
    let cache = try #require(PlanLimits.fromClaudeConfig(Data(claudeConfig.utf8)))  // fetched 1800000600
    let now = at(1800001000)
    #expect(PlanLimits.choose(statusLine: line, cache: cache, now: now)?.source == .claudeCache)

    let newerLine = PlanLimits(fiveHour: .init(percent: 30, resetsAt: at(1800003600)), sevenDay: nil,
                               source: .statusLine, fetchedAt: at(1800000900))
    let chosen = try #require(PlanLimits.choose(statusLine: newerLine, cache: cache, now: now))
    #expect(chosen.source == .statusLine)
    #expect(chosen.fiveHour?.percent == 30)
    // the model-scoped limit only exists in the cache and is carried over
    #expect(chosen.scoped.map(\.name) == ["Lyra"])

    #expect(PlanLimits.choose(statusLine: nil, cache: cache, now: now)?.source == .claudeCache)
    #expect(PlanLimits.choose(statusLine: line, cache: nil, now: now)?.source == .statusLine)
    #expect(PlanLimits.choose(statusLine: nil, cache: nil, now: now) == nil)
}

@Test func olderSourceWinsWhenNewerIsExpired() throws {
    let cache = try #require(PlanLimits.fromClaudeConfig(Data(claudeConfig.utf8)))
    let expired = PlanLimits(fiveHour: .init(percent: 30, resetsAt: at(1800000950)), sevenDay: nil,
                             source: .statusLine, fetchedAt: at(1800000900))
    #expect(PlanLimits.choose(statusLine: expired, cache: cache, now: at(1800001000))?.source == .claudeCache)
}

@Test func rewriteWithSameNumbersIsNoNews() {
    func line(_ percent: Double, written: TimeInterval) -> PlanLimits {
        PlanLimits(fiveHour: .init(percent: percent, resetsAt: at(1800003600)), sevenDay: nil,
                   source: .statusLine, fetchedAt: at(written))
    }
    let old = line(30, written: 1800000000)
    // the status line rewrites the file on every turn: only a new time stamp is not worth a redraw
    #expect(!line(30, written: 1800000020).isNews(after: old))
    #expect(line(31, written: 1800000020).isNews(after: old))
    // the popover shows the age by the minute, so a minute later it is news again
    #expect(line(30, written: 1800000060).isNews(after: old))
    #expect(line(30, written: 1800000000).isNews(after: nil))
}

@Test func countdownFormat() {
    #expect(UsageFormat.countdown(-5) == "<1m")
    #expect(UsageFormat.countdown(59) == "<1m")
    #expect(UsageFormat.countdown(45 * 60 + 30) == "45m")
    #expect(UsageFormat.countdown(2 * 3600 + 14 * 60) == "2h 14m")
    #expect(UsageFormat.countdown(27 * 3600 + 5 * 60) == "1d 3h")
}

@Test func tokenFormat() {
    #expect(UsageFormat.tokens(812) == "812")
    #expect(UsageFormat.tokens(45_230) == "45.2k")
    #expect(UsageFormat.tokens(3_100_000) == "3.1M")
    #expect(UsageFormat.tokens(250_000_000) == "250M")
    #expect(UsageFormat.age(125) == "2 min")
}

@Test func usdFormatting() {
    #expect(UsageFormat.usd(0.001) == "$0")
    #expect(UsageFormat.usd(0.42) == "$0.42")
    #expect(UsageFormat.usd(38.4) == "$38")
    #expect(UsageFormat.usd(1240.2) == "$1,240")
}

// MARK: Pace

@Test func paceProjectsLinearlyToTheReset() throws {
    // 5h window, 2h left → 3h elapsed; 30 % used → 50 % at the reset
    let w = PlanLimits.Window(percent: 30, resetsAt: at(1_800_007_200))
    let p = try #require(w.pace(length: PlanLimits.fiveHourLength, now: at(1_800_000_000)))
    #expect(abs(p.projectedPercent - 50) < 0.001)
    #expect(p.lasts)
    #expect(p.runsOutIn == nil)
}

@Test func paceSaysWhenItRunsOut() throws {
    // 1h elapsed, 4h left, 40 % used → 200 % at the reset; 60 % left at 40 %/h → empty in 1.5h
    let w = PlanLimits.Window(percent: 40, resetsAt: at(1_800_014_400))
    let p = try #require(w.pace(length: PlanLimits.fiveHourLength, now: at(1_800_000_000)))
    #expect(!p.lasts)
    #expect(abs(try #require(p.runsOutIn) - 5400) < 0.001)
}

@Test func paceNeedsTenPercentOfTheWindowAndAResetTime() {
    let early = PlanLimits.Window(percent: 5, resetsAt: at(1_800_000_000 + 18_000 - 1_000))
    #expect(early.pace(length: PlanLimits.fiveHourLength, now: at(1_800_000_000)) == nil)
    #expect(PlanLimits.Window(percent: 5, resetsAt: nil).pace(length: PlanLimits.fiveHourLength, now: at(0)) == nil)
}

@Test func outlookFollowsThePaceNotTheUsage() {
    let now = at(1_800_000_000), len = PlanLimits.fiveHourLength
    // 4h elapsed, 1h left
    let reset = at(1_800_003_600)
    // 70 % used → 87.5 % at the reset: lasts, however full it already is
    #expect(PlanLimits.Window(percent: 70, resetsAt: reset).outlook(length: len, now: now) == .lasts)
    // 76 % → 95 %: tight
    #expect(PlanLimits.Window(percent: 76, resetsAt: reset).outlook(length: len, now: now) == .tight)
    // 84 % → 105 %: runs out
    #expect(PlanLimits.Window(percent: 84, resetsAt: reset).outlook(length: len, now: now) == .runsOut)
    // 1h elapsed, 30 % used → 150 %: runs out although little is used
    #expect(PlanLimits.Window(percent: 30, resetsAt: at(1_800_014_400)).outlook(length: len, now: now) == .runsOut)
    // no pace yet: no outlook, unless the limit is reached
    #expect(PlanLimits.Window(percent: 5, resetsAt: nil).outlook(length: len, now: now) == nil)
    #expect(PlanLimits.Window(percent: 100, resetsAt: nil).outlook(length: len, now: now) == .runsOut)
}

@Test func paceAtTheLimitDoesNotLast() throws {
    let w = PlanLimits.Window(percent: 100, resetsAt: at(1_800_003_600))
    let p = try #require(w.pace(length: PlanLimits.fiveHourLength, now: at(1_800_000_000)))
    #expect(!p.lasts)
    #expect(p.runsOutIn == 0)
}
