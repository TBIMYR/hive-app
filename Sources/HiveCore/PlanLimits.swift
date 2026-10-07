import Foundation

/// Plan limits (5-hour and weekly window) from the status line file or from Claude Code's cache.
public struct PlanLimits: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        /// `~/.claude/hive/usage.json`, written by the status line script
        case statusLine
        /// `cachedUsageUtilization` in `~/.claude.json`
        case claudeCache
    }

    public struct Window: Equatable, Sendable {
        /// 0–100
        public let percent: Double
        public let resetsAt: Date?

        public init(percent: Double, resetsAt: Date?) {
            self.percent = percent
            self.resetsAt = resetsAt
        }

        /// Linear projection at the pace so far in this window. nil without a reset time or while less
        /// than a tenth of the window has passed (too early to say).
        public func pace(length: TimeInterval, now: Date) -> Pace? {
            guard let resetsAt else { return nil }
            let elapsed = length - resetsAt.timeIntervalSince(now)
            guard elapsed >= length / 10, elapsed <= length else { return nil }
            let perSecond = percent / elapsed
            let projected = perSecond * length
            let runsOutIn: TimeInterval? = projected < 100 ? nil : (perSecond > 0 ? max(0, (100 - percent) / perSecond) : nil)
            return Pace(projectedPercent: projected, runsOutIn: runsOutIn)
        }
    }

    public struct Pace: Equatable, Sendable {
        /// where the window ends up at the reset if the pace stays the same
        public let projectedPercent: Double
        /// time until 100 % at this pace; nil if it lasts until the reset
        public let runsOutIn: TimeInterval?

        public var lasts: Bool { runsOutIn == nil }
    }

    public static let fiveHourLength: TimeInterval = 5 * 3600
    public static let weekLength: TimeInterval = 7 * 86400

    /// Weekly limit for one model (from `limits[]` with `kind: weekly_scoped`)
    public struct Scoped: Equatable, Sendable {
        public let name: String
        public let window: Window

        public init(name: String, window: Window) {
            self.name = name
            self.window = window
        }
    }

    public var fiveHour: Window?
    public var sevenDay: Window?
    public var scoped: [Scoped]
    public let source: Source
    /// when the source wrote or fetched the values
    public let fetchedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, scoped: [Scoped] = [], source: Source, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.scoped = scoped
        self.source = source
        self.fetchedAt = fetchedAt
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil && scoped.isEmpty }

    // MARK: Parsing

    /// `{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":<epoch s>},…},"written_at":<epoch s>}`
    public static func fromStatusLine(_ data: Data) -> PlanLimits? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = j["rate_limits"] as? [String: Any],
              let written = number(j["written_at"]) else { return nil }
        func window(_ key: String) -> Window? {
            guard let w = limits[key] as? [String: Any], let p = number(w["used_percentage"]) else { return nil }
            return Window(percent: p, resetsAt: number(w["resets_at"]).map { Date(timeIntervalSince1970: $0) })
        }
        let result = PlanLimits(fiveHour: window("five_hour"), sevenDay: window("seven_day"),
                                source: .statusLine, fetchedAt: Date(timeIntervalSince1970: written))
        return result.isEmpty ? nil : result
    }

    /// Only the key `cachedUsageUtilization` of `~/.claude.json` is read; the rest of the file
    /// (which holds account and OAuth data) is dropped right after parsing.
    public static func fromClaudeConfig(_ data: Data) -> PlanLimits? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any] else { return nil }
        return fromCachedUtilization(cache)
    }

    static func fromCachedUtilization(_ c: [String: Any]) -> PlanLimits? {
        guard let fetchedMs = number(c["fetchedAtMs"]) else { return nil }
        let util = c["utilization"] as? [String: Any] ?? [:]
        let limits = (util["limits"] as? [Any] ?? c["limits"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        func date(_ v: Any?) -> Date? { string(v).flatMap(parseISO) }
        func fromUtil(_ key: String) -> Window? {
            guard let w = util[key] as? [String: Any], let p = number(w["utilization"]) else { return nil }
            return Window(percent: p, resetsAt: date(w["resets_at"]))
        }
        func fromLimits(_ kind: String) -> Window? {
            guard let l = limits.first(where: { $0["kind"] as? String == kind }), let p = number(l["percent"]) else { return nil }
            return Window(percent: p, resetsAt: date(l["resets_at"]))
        }
        let scoped: [Scoped] = limits.compactMap { l in
            guard l["kind"] as? String == "weekly_scoped", let p = number(l["percent"]) else { return nil }
            let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"]
            return Scoped(name: string(model) ?? "Model", window: Window(percent: p, resetsAt: date(l["resets_at"])))
        }
        let result = PlanLimits(fiveHour: fromUtil("five_hour") ?? fromLimits("session"),
                                sevenDay: fromUtil("seven_day") ?? fromLimits("weekly_all"),
                                scoped: scoped, source: .claudeCache,
                                fetchedAt: Date(timeIntervalSince1970: fetchedMs / 1000))
        return result.isEmpty ? nil : result
    }

    // MARK: Choosing

    /// Without windows whose reset time has passed (their percentage no longer applies); nil if nothing is left.
    public func droppingExpired(now: Date) -> PlanLimits? {
        func live(_ w: Window?) -> Window? {
            guard let w else { return nil }
            if let r = w.resetsAt, r <= now { return nil }
            return w
        }
        var copy = self
        copy.fiveHour = live(fiveHour)
        copy.sevenDay = live(sevenDay)
        copy.scoped = scoped.filter { live($0.window) != nil }
        return copy.isEmpty ? nil : copy
    }

    /// The newer of both sources (after dropping expired windows). Model-scoped limits only exist in the
    /// cache, so they are carried over from there when the status line wins.
    public static func choose(statusLine: PlanLimits?, cache: PlanLimits?, now: Date) -> PlanLimits? {
        let a = statusLine?.droppingExpired(now: now)
        let b = cache?.droppingExpired(now: now)
        guard let a else { return b }
        guard let b else { return a }
        if b.fetchedAt > a.fetchedAt { return b }
        var merged = a
        merged.scoped = b.scoped
        return merged
    }

    public static let defaultStatusLinePath = "\(home)/.claude/hive/usage.json"
    public static let defaultClaudeConfigPath = "\(home)/.claude.json"

    /// Reads both files and chooses. Read errors count as "no data".
    public static func load(statusLinePath: String = defaultStatusLinePath,
                            claudeConfigPath: String = defaultClaudeConfigPath, now: Date = Date()) -> PlanLimits? {
        let a = FileManager.default.contents(atPath: statusLinePath).flatMap(fromStatusLine)
        let b = FileManager.default.contents(atPath: claudeConfigPath).flatMap(fromClaudeConfig)
        return choose(statusLine: a, cache: b, now: now)
    }
}

// MARK: Display helpers

public enum UsageFormat {
    /// "<1m", "45m", "2h 14m", "1d 3h" (rounded down, never negative)
    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "<1m" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h \(m % 60)m" }
        return "\(h / 24)d \(h % 24)h"
    }

    /// "<1 min", "2 min", "1 h", "3 d" for the age of the data
    public static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "<1 min" }
        if s < 3600 { return "\(s / 60) min" }
        if s < 86400 { return "\(s / 3600) h" }
        return "\(s / 86400) d"
    }

    /// "812", "45.2k", "3.1M", "1.2B"
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        func short(_ v: Double, _ unit: String) -> String {
            let text = v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
            return text + unit
        }
        if n < 1000 { return "\(n)" }
        if n < 1_000_000 { return short(d / 1000, "k") }
        if n < 1_000_000_000 { return short(d / 1_000_000, "M") }
        return short(d / 1_000_000_000, "B")
    }

    /// "$0.42", "$38", "$1,240" (dollars at API list prices)
    public static func usd(_ v: Double) -> String {
        if v < 0.005 { return "$0" }
        if v < 10 { return String(format: "$%.2f", v) }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v.rounded())) ?? String(format: "%.0f", v))
    }

    public enum Level: Equatable, Sendable { case normal, warning, critical }

    /// below 70 % normal, 70–89 % warning, from 90 % critical
    public static func level(_ percent: Double) -> Level {
        percent >= 90 ? .critical : percent >= 70 ? .warning : .normal
    }
}
