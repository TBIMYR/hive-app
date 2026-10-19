import Foundation

/// Token counts of one or more responses (as in `message.usage`).
public struct TokenCounts: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var cacheCreation = 0
    /// part of `cacheCreation` written with the 1-hour TTL (priced higher)
    public var cacheCreation1h = 0
    public var cacheRead = 0
    /// value at API list prices (ModelPricing); only filled when aggregating
    public var usd: Double = 0

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheCreation1h: Int = 0, cacheRead: Int = 0,
                usd: Double = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheCreation1h = cacheCreation1h
        self.cacheRead = cacheRead
        self.usd = usd
    }

    /// everything together; usually dominated by cache reads
    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(input: a.input + b.input, output: a.output + b.output,
                    cacheCreation: a.cacheCreation + b.cacheCreation, cacheCreation1h: a.cacheCreation1h + b.cacheCreation1h,
                    cacheRead: a.cacheRead + b.cacheRead, usd: a.usd + b.usd)
    }

    public static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }

    /// Field by field the larger value (several transcript lines of one streamed response).
    func merged(_ o: TokenCounts) -> TokenCounts {
        TokenCounts(input: max(input, o.input), output: max(output, o.output),
                    cacheCreation: max(cacheCreation, o.cacheCreation), cacheCreation1h: max(cacheCreation1h, o.cacheCreation1h),
                    cacheRead: max(cacheRead, o.cacheRead))
    }
}

/// One model response from a transcript.
public struct UsageRecord: Equatable, Sendable {
    /// `message.id|requestId`, the same for all lines of a response
    public let key: String
    public let at: Date
    public let model: String?
    public let project: String
    public let sessionId: String
    public var tokens: TokenCounts
}

/// A period of whole days ending today (in the calendar's time zone).
public enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    /// today and the days before it
    public var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    public var id: String { rawValue }
}

/// Token usage per day over the last 31 days, per project and per session, so any period can be summed.
public struct UsageStats: Equatable, Sendable {
    /// number of days kept: 30 for the longest period plus one so the scan never cuts into it
    public static let keptDays = 31

    public struct Day: Equatable, Sendable {
        /// start of the day in the calendar's time zone
        public let start: Date
        public var tokens = TokenCounts()
        /// project name → tokens
        public var projects: [String: TokenCounts] = [:]
        /// session name → tokens
        public var sessions: [String: TokenCounts] = [:]
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public let name: String
        public var tokens: TokenCounts
        public var id: String { name }
    }

    /// index 0 = today, 30 = thirty days ago
    public var days: [Day] = []

    public init() {}

    public func tokens(_ period: UsagePeriod) -> TokenCounts {
        days.prefix(period.days).reduce(TokenCounts()) { $0 + $1.tokens }
    }

    public var today: TokenCounts { tokens(.today) }
    public var last7Days: TokenCounts { tokens(.week) }
    public var last30Days: TokenCounts { tokens(.month) }

    /// sorted by total, largest first
    public func projects(_ period: UsagePeriod) -> [Row] { rows(period, \.projects) }
    public func sessions(_ period: UsagePeriod) -> [Row] { rows(period, \.sessions) }

    private func rows(_ period: UsagePeriod, _ field: KeyPath<Day, [String: TokenCounts]>) -> [Row] {
        var sum: [String: TokenCounts] = [:]
        for d in days.prefix(period.days) {
            for (name, t) in d[keyPath: field] { sum[name, default: TokenCounts()] += t }
        }
        return sum.map { Row(name: $0.key, tokens: $0.value) }.sorted {
            $0.tokens.total != $1.tokens.total ? $0.tokens.total > $1.tokens.total : $0.name < $1.name
        }
    }

    /// Start of the oldest kept day: records and files before it are not needed.
    public static func cutoff(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(keptDays - 1), to: today) ?? today
    }

    /// Session names come from `titles` (session id → name), otherwise the first 8 characters of the id.
    public static func aggregate<S: Sequence>(_ records: S, titles: [String: String], now: Date,
                                              calendar: Calendar) -> UsageStats where S.Element == UsageRecord {
        var stats = UsageStats()
        let today = calendar.startOfDay(for: now)
        stats.days = (0..<keptDays).map { i in
            Day(start: calendar.date(byAdding: .day, value: -i, to: today) ?? today)
        }
        // the day of a record by comparing with the day starts: calendar calls per record (ICU time zones)
        // made every rescan cost about a second with a month of transcripts
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? .distantFuture
        for r in records {
            guard r.at < tomorrow, let i = stats.days.firstIndex(where: { $0.start <= r.at }) else { continue }
            var t = r.tokens
            t.usd = ModelPricing.usd(model: r.model, t) ?? 0
            stats.days[i].tokens += t
            stats.days[i].projects[r.project.isEmpty ? "?" : r.project, default: TokenCounts()] += t
            stats.days[i].sessions[titles[r.sessionId] ?? String(r.sessionId.prefix(8)), default: TokenCounts()] += t
        }
        return stats
    }
}

/// Reads the token usage from the transcripts `<projects>/<slug>/<sessionId>.jsonl` and
/// `<projects>/<slug>/<sessionId>/subagents/agent-*.jsonl` of the last 31 days. Incremental: every
/// file is only read on from where the last scan stopped (complete lines only). Scans are serialized
/// by a lock, so it can be handed to a background queue.
public final class UsageScanner: @unchecked Sendable {
    static let chunk = 4 * 1024 * 1024

    private struct FileState {
        var offset: UInt64 = 0
        var size: UInt64 = 0
        var mtime = Date.distantPast
        let fallbackProject: String
    }

    let projectsDir: String
    let devRoot: String
    let calendar: Calendar
    private var files: [String: FileState] = [:]
    private var records: [String: UsageRecord] = [:]
    /// session id → name from `custom-title` / `agent-name` lines
    private var titles: [String: String] = [:]

    public init(projectsDir: String = "\(StateBuilder.defaultClaudeHome)/projects",
                devRoot: String = Project.defaultDevRoot, calendar: Calendar = .current) {
        self.projectsDir = projectsDir
        self.devRoot = devRoot
        self.calendar = calendar
    }

    /// number of transcript files currently followed
    public var trackedFiles: Int { lock.withLock { files.count } }

    private let lock = NSLock()

    public func scan(now: Date = Date()) -> UsageStats {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = UsageStats.cutoff(now: now, calendar: calendar)
        var seen = Set<String>()
        for (path, attrs, project) in transcriptFiles(modifiedAfter: cutoff) {
            seen.insert(path)
            read(path, attrs: attrs, fallbackProject: project)
        }
        files = files.filter { seen.contains($0.key) }
        records = records.filter { $0.value.at >= cutoff }
        return UsageStats.aggregate(records.values, titles: titles, now: now, calendar: calendar)
    }

    // MARK: Files

    private typealias Attrs = (size: UInt64, mtime: Date)

    private func attributes(_ path: String) -> (type: FileAttributeType, attrs: Attrs)? {
        // attributesOfItem does not follow a symlink at the end of the path
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let type = a[.type] as? FileAttributeType else { return nil }
        let size = (a[.size] as? NSNumber)?.uint64Value ?? 0
        return (type, (size, a[.modificationDate] as? Date ?? .distantPast))
    }

    private func transcriptFiles(modifiedAfter cutoff: Date) -> [(String, Attrs, String)] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsDir) else { return [] }
        var out: [(String, Attrs, String)] = []
        for d in dirs.sorted() {
            let dir = "\(projectsDir)/\(d)"
            // symlinked project folders point to another folder that is read anyway
            guard attributes(dir)?.type == .typeDirectory, let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            let project = Project.fromCwd(d)
            for e in entries {
                let path = "\(dir)/\(e)"
                guard let (type, attrs) = attributes(path) else { continue }
                if type == .typeRegular, e.hasSuffix(".jsonl") {
                    if attrs.mtime >= cutoff { out.append((path, attrs, project)) }
                } else if type == .typeDirectory {
                    let sub = "\(path)/subagents"
                    for f in (try? fm.contentsOfDirectory(atPath: sub)) ?? [] where f.hasSuffix(".jsonl") {
                        let p = "\(sub)/\(f)"
                        if let (t, a) = attributes(p), t == .typeRegular, a.mtime >= cutoff { out.append((p, a, project)) }
                    }
                }
            }
        }
        return out
    }

    private func read(_ path: String, attrs: Attrs, fallbackProject: String) {
        if let known = files[path], known.size == attrs.size, known.mtime == attrs.mtime { return }
        var state = files[path] ?? FileState(fallbackProject: fallbackProject)
        // rewritten or truncated: start over (the dedupe keeps already counted responses single)
        if attrs.size < state.offset { state.offset = 0 }
        defer {
            state.size = attrs.size
            state.mtime = attrs.mtime
            files[path] = state
        }
        guard let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: state.offset)) != nil else { return }
        var carry = Data()
        while true {
            guard let data = try? h.read(upToCount: Self.chunk), !data.isEmpty else { break }
            var buffer = carry
            buffer.append(data)
            let consumed = processLines(buffer, fallbackProject: state.fallbackProject)
            // the buffer starts at `state.offset` (the carried bytes were not counted yet)
            state.offset += UInt64(consumed)
            carry = consumed < buffer.count ? buffer.subdata(in: consumed..<buffer.count) : Data()
        }
    }

    private static let usageNeedle = Array(#""usage":{"#.utf8)
    private static let assistantNeedle = Array(#""type":"assistant""#.utf8)
    private static let titleNeedle = Array(#""custom-title""#.utf8)
    private static let agentNeedle = Array(#""agent-name""#.utf8)

    /// Handles all complete lines in `buffer`; returns the number of bytes consumed (up to the last newline).
    private func processLines(_ buffer: Data, fallbackProject: String) -> Int {
        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return 0 }
            var start = 0
            while start < raw.count {
                guard let nl = memchr(base + start, 0x0A, raw.count - start) else { break }
                let end = base.distance(to: nl)
                let len = end - start
                if len > 0 { handleLine(base + start, len, fallbackProject: fallbackProject) }
                start = end + 1
            }
            return start
        }
    }

    private func contains(_ p: UnsafeRawPointer, _ len: Int, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { n in memmem(p, len, n.baseAddress, n.count) != nil }
    }

    private func handleLine(_ p: UnsafeRawPointer, _ len: Int, fallbackProject: String) {
        let usage = contains(p, len, Self.usageNeedle) && contains(p, len, Self.assistantNeedle)
        // title lines are short; long lines (tool results) are not searched for them
        let title = !usage && len < 4096 && (contains(p, len, Self.titleNeedle) || contains(p, len, Self.agentNeedle))
        guard usage || title else { return }
        guard let line = Line.parse(p.assumingMemoryBound(to: UInt8.self), count: len) else { return }
        if title {
            guard let sid = line.sessionId.nonEmpty else { return }
            switch line.type {
            case "custom-title": if let t = line.customTitle.nonEmpty { titles[sid] = t }
            case "agent-name": if titles[sid] == nil, let t = line.agentName.nonEmpty { titles[sid] = t }
            default: break
            }
            return
        }
        guard let r = Self.record(line, devRoot: devRoot, fallbackProject: fallbackProject) else { return }
        if var old = records[r.key] {
            old.tokens = old.tokens.merged(r.tokens)
            records[r.key] = old
        } else {
            records[r.key] = r
        }
    }

    /// Only the fields the scanner needs; everything else (message content, tool inputs) is skipped unread.
    struct Line {
        struct Usage {
            var input: Double?
            var output: Double?
            var cacheCreation: Double?
            var cacheCreation1h: Double?
            var cacheRead: Double?
        }
        var type: String?
        var sessionId: String?
        var timestamp: String?
        var requestId: String?
        var uuid: String?
        var cwd: String?
        var customTitle: String?
        var agentName: String?
        var messageId: String?
        var model: String?
        var usage: Usage?

        static func parse(_ text: String) -> Line? {
            Array(text.utf8).withUnsafeBufferPointer { b in b.baseAddress.flatMap { parse($0, count: b.count) } }
        }

        static func parse(_ p: UnsafePointer<UInt8>, count: Int) -> Line? {
            var line = Line()
            var skim = JSONSkim(p, count: count)
            let ok = skim.object { s, key in
                func str(_ assign: (String?) -> Void) -> Bool {
                    let (ok, v) = s.stringOrSkip()
                    assign(v)
                    return ok
                }
                switch key {
                case "type": return str { line.type = $0 }
                case "sessionId": return str { line.sessionId = $0 }
                case "timestamp": return str { line.timestamp = $0 }
                case "requestId": return str { line.requestId = $0 }
                case "uuid": return str { line.uuid = $0 }
                case "cwd": return str { line.cwd = $0 }
                case "customTitle": return str { line.customTitle = $0 }
                case "agentName": return str { line.agentName = $0 }
                case "message":
                    guard s.peekObject else { return s.skip() }
                    return s.object { m, key in
                        switch key {
                        case "id":
                            let (ok, v) = m.stringOrSkip(); line.messageId = v; return ok
                        case "model":
                            let (ok, v) = m.stringOrSkip(); line.model = v; return ok
                        case "usage":
                            guard m.peekObject else { return m.skip() }
                            var u = Usage()
                            let ok = m.object { n, key in
                                switch key {
                                case "input_tokens": let (ok, v) = n.number(); u.input = v; return ok
                                case "output_tokens": let (ok, v) = n.number(); u.output = v; return ok
                                case "cache_creation_input_tokens": let (ok, v) = n.number(); u.cacheCreation = v; return ok
                                case "cache_read_input_tokens": let (ok, v) = n.number(); u.cacheRead = v; return ok
                                case "cache_creation":
                                    guard n.peekObject else { return n.skip() }
                                    return n.object { c, key in
                                        guard key == "ephemeral_1h_input_tokens" else { return c.skip() }
                                        let (ok, v) = c.number(); u.cacheCreation1h = v; return ok
                                    }
                                default: return n.skip()
                                }
                            }
                            line.usage = u
                            return ok
                        default:
                            return m.skip()
                        }
                    }
                default:
                    return s.skip()
                }
            }
            return ok ? line : nil
        }
    }

    /// Usage of an assistant line, nil for every other line.
    static func record(_ line: Line, devRoot: String, fallbackProject: String) -> UsageRecord? {
        guard line.type == "assistant", let u = line.usage,
              let at = line.timestamp.nonEmpty.flatMap(fastISO) else { return nil }
        func n(_ v: Double?) -> Int { v.flatMap { Int(exactly: $0.rounded()) } ?? 0 }
        let id = line.messageId.nonEmpty ?? line.uuid.nonEmpty ?? ""
        let project = line.cwd.nonEmpty.map { Project.fromCwd($0, devRoot: devRoot) } ?? fallbackProject
        return UsageRecord(key: "\(id)|\(line.requestId ?? "")", at: at, model: line.model.nonEmpty, project: project,
                           sessionId: line.sessionId.nonEmpty ?? "?",
                           tokens: TokenCounts(input: n(u.input), output: n(u.output),
                                               cacheCreation: n(u.cacheCreation), cacheCreation1h: n(u.cacheCreation1h),
                                               cacheRead: n(u.cacheRead)))
    }
}

/// "2027-01-15T10:00:00.123Z" without a date formatter (ICU made it the slowest part of the first scan);
/// anything else goes through `parseISO`.
func fastISO(_ s: String) -> Date? {
    let u = Array(s.utf8)
    func digits(_ from: Int, _ count: Int) -> Int? {
        var v = 0
        for k in from..<(from + count) {
            guard k < u.count, u[k] >= 48, u[k] <= 57 else { return nil }
            v = v * 10 + Int(u[k] - 48)
        }
        return v
    }
    guard u.count >= 20, u.last == UInt8(ascii: "Z"), u[4] == 45, u[7] == 45, u[10] == 84, u[13] == 58, u[16] == 58,
          let y = digits(0, 4), let mo = digits(5, 2), let d = digits(8, 2),
          let h = digits(11, 2), let mi = digits(14, 2), let sec = digits(17, 2) else { return parseISO(s) }
    var frac = 0.0
    if u.count > 20 {
        guard u[19] == 46, let f = digits(20, u.count - 21) else { return parseISO(s) }
        frac = Double(f) / pow(10, Double(u.count - 21))
    }
    var t = tm()
    t.tm_year = Int32(y - 1900); t.tm_mon = Int32(mo - 1); t.tm_mday = Int32(d)
    t.tm_hour = Int32(h); t.tm_min = Int32(mi); t.tm_sec = Int32(sec)
    return Date(timeIntervalSince1970: Double(timegm(&t)) + frac)
}
