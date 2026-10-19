import SwiftUI
import HiveCore

/// Plan limits (status line file or Claude Code's cache) and token usage from the transcripts.
/// Reading happens on its own serial queue; the first transcript scan takes a few seconds,
/// later ones only read what was appended.
@MainActor
final class UsageStore: ObservableObject {
    /// Chosen source at the last read; the views drop windows that expired since (see `current(now:)`)
    @Published private(set) var limits: PlanLimits?
    @Published private(set) var stats: UsageStats?

    private let scanner = UsageScanner()
    private let queue = DispatchQueue(label: "hive.usage", qos: .utility)
    private var scanning = false
    private var scannedAt = Date.distantPast
    private var timer: Timer?
    private var limitsWatcher: Watcher?
    private var transcriptWatcher: Watcher?

    init() {
        reloadLimits()
        rescan()
        let home = StateBuilder.defaultClaudeHome
        // the status line script writes usage.json atomically into ~/.claude/hive
        limitsWatcher = Watcher(paths: ["\(home)/hive"]) { [weak self] in
            Task { @MainActor in self?.reloadLimits() }
        }
        // transcripts change all the time: at most one scan per minute from events (nobody reads the token
        // numbers by the second)
        transcriptWatcher = Watcher(paths: ["\(home)/projects"], delay: 60) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        // ~/.claude.json is not watched (its folder is the home folder): the timer picks it up; a scan every
        // 5 min moves the days on after midnight even when no transcript changes
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.reloadLimits()
                if Date().timeIntervalSince(self.scannedAt) >= 300 { self.rescan() }
            }
        }
    }

    func current(now: Date) -> PlanLimits? { limits?.droppingExpired(now: now) }

    func reloadLimits() {
        queue.async { [weak self] in
            let l = PlanLimits.load()
            Task { @MainActor in
                guard let self else { return }
                if let l, l.isNews(after: self.limits) { self.limits = l } else if l == nil, self.limits != nil { self.limits = nil }
            }
        }
    }

    func rescan() {
        guard !scanning else { return }
        scanning = true
        scannedAt = Date()
        let scanner = scanner
        queue.async { [weak self] in
            #if DEBUG
            let first = scanner.trackedFiles == 0
            let started = Date()
            let s = scanner.scan()
            if first { NSLog("hive: first usage scan %.1f s, %d files", Date().timeIntervalSince(started), scanner.trackedFiles) }
            #else
            let s = scanner.scan()
            #endif
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                if self.stats != s { self.stats = s }
            }
        }
    }
}

private extension PlanLimits.Outlook {
    /// green: lasts until the reset, orange: gets tight, red: runs out before it
    var color: Color {
        switch self {
        case .lasts: Hive.busy
        case .tight: Hive.block
        case .runsOut: Hive.need
        }
    }
}

/// Title bar: "5h 19% (2h 14m) · Week 78% (1d 3h)"; click opens the details as a floating card.
struct UsageButton: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: StateStore
    @State private var card = FloatingCard()
    @State private var anchor: NSView?

    var body: some View {
        let now = store.now
        if let limits = usage.current(now: now) {
            Button { toggle() } label: { label(limits, now: now) }
                .buttonStyle(.plain)
                // on macOS 26 the item sits on a glass capsule: a bit more room on the left looks balanced
                .padding(.leading, 14).padding(.trailing, 7)
                .background { AnchorReader { anchor = $0 } }
                .help("Plan usage")
                .onDisappear { card.close() }
                #if DEBUG
                // for screenshots of a test instance: HIVE_OPEN_USAGE=1 opens the details at launch
                .task {
                    guard ProcessInfo.processInfo.environment["HIVE_OPEN_USAGE"] != nil else { return }
                    try? await Task.sleep(for: .seconds(2))
                    NSApp.activate(ignoringOtherApps: true)
                    try? await Task.sleep(for: .seconds(1))
                    toggle()
                }
                #endif
        }
    }

    private func toggle() {
        let (usage, store) = (usage, store)
        card.toggle(below: anchor) { UsagePopover().environmentObject(usage).environmentObject(store) }
    }

    private func label(_ l: PlanLimits, now: Date) -> some View {
        var parts: [Text] = []
        if let w = l.fiveHour { parts.append(part("5h", w, length: PlanLimits.fiveHourLength, now: now)) }
        if let w = l.sevenDay { parts.append(part("Week", w, length: PlanLimits.weekLength, now: now)) }
        if parts.isEmpty, let s = l.scoped.first { parts.append(part(s.name, s.window, length: PlanLimits.weekLength, now: now)) }
        let joined = parts.dropFirst().reduce(parts.first ?? Text("")) { a, b in
            a + Text("  ·  ").foregroundColor(Hive.hair2) + b
        }
        return joined.font(.system(size: 12.5, weight: .medium)).monospacedDigit().lineLimit(1).fixedSize()
    }

    private func part(_ name: String, _ w: PlanLimits.Window, length: TimeInterval, now: Date) -> Text {
        // colored like the arrow: what counts is whether it lasts, not how much is used
        var main = Text("\(name) \(Int(w.percent.rounded()))%")
            .foregroundColor(w.outlook(length: length, now: now)?.color ?? Hive.ink2)
        if let pace = w.pace(length: length, now: now) { main = main + Text(" ") + PaceArrow.text(pace) }
        guard let r = w.resetsAt else { return main }
        return main + Text(" (\(UsageFormat.countdown(r.timeIntervalSince(now))))")
            .font(.system(size: 11)).foregroundColor(Hive.muted)
    }
}

/// Details: both limits with bars and countdown, source, then tokens over 1/7/30 days and the top projects
/// and sessions of the chosen period.
struct UsagePopover: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: StateStore
    @AppStorage("usagePeriod") private var period: UsagePeriod = .week

    var body: some View {
        let now = store.now
        VStack(alignment: .leading, spacing: 16) {
            if let l = usage.current(now: now) {
                VStack(alignment: .leading, spacing: 14) {
                    if let w = l.fiveHour { LimitRow(title: "Session (5 hours)", window: w, length: PlanLimits.fiveHourLength, now: now) }
                    if let w = l.sevenDay { LimitRow(title: "Week", window: w, length: PlanLimits.weekLength, now: now) }
                    ForEach(l.scoped, id: \.name) { s in
                        LimitRow(title: "Week · \(s.name)", window: s.window, length: PlanLimits.weekLength, now: now)
                    }
                }
                Text(source(l, now: now)).font(.system(size: 11.5)).foregroundStyle(Hive.muted)
            }
            Rectangle().fill(Hive.hair).frame(height: 1)
            if let s = usage.stats {
                tokens(s)
            } else {
                Text("Reading transcripts…").font(.system(size: 12.5)).foregroundStyle(Hive.muted)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Hive.card)
    }

    private func source(_ l: PlanLimits, now: Date) -> String {
        let from = l.source == .statusLine ? "from status line" : "from Claude Code cache"
        let age = UsageFormat.age(now.timeIntervalSince(l.fetchedAt))
        return "\(from), \(age == "<1 min" ? "just now" : "\(age) ago")"
    }

    @ViewBuilder
    private func tokens(_ s: UsageStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokens").font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
                Spacer()
                Text("Output").frame(width: 64, alignment: .trailing)
                Text("Total").frame(width: 64, alignment: .trailing)
                Text("API $").frame(width: 64, alignment: .trailing)
                    .help("What these tokens would cost at Anthropic's API list prices (input, output, cache writes and reads per model). Your plan is a flat fee.")
            }
            .font(.system(size: 11.5)).foregroundStyle(Hive.muted)
            TokenRow(name: "Today", tokens: s.today, bold: true)
            TokenRow(name: "Last 7 days", tokens: s.last7Days, bold: true)
            TokenRow(name: "Last 30 days", tokens: s.last30Days, bold: true)
            DayBars(days: Array(s.days.prefix(UsagePeriod.month.days)))
                .padding(.top, 4)
            Text(cacheNote(s)).font(.system(size: 11.5)).foregroundStyle(Hive.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        Rectangle().fill(Hive.hair).frame(height: 1)
        PeriodSwitcher(period: $period)
        let projects = s.projects(period)
        let sessions = s.sessions(period)
        if projects.isEmpty && sessions.isEmpty {
            Text("No usage \(period == .today ? "today" : "in the last \(period.label)").")
                .font(.system(size: 12.5)).foregroundStyle(Hive.muted)
        }
        if !projects.isEmpty { section("Top projects · \(period.label.lowercased())", projects) }
        if !sessions.isEmpty { section("Top sessions · \(period.label.lowercased())", sessions) }
    }

    private func cacheNote(_ s: UsageStats) -> String {
        let t = s.last30Days
        let api = "API $: value at Anthropic's API list prices; your plan is a flat fee."
        guard t.total > 0 else { return "Output per day over 30 days. Total includes cache reads. " + api }
        let share = Int((Double(t.cacheRead) / Double(t.total) * 100).rounded())
        return "Output per day over 30 days. Total includes cache reads (\(share) % of it). " + api
    }

    private func section(_ title: String, _ rows: [UsageStats.Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
            ForEach(rows.prefix(5)) { r in TokenRow(name: r.name, tokens: r.tokens) }
        }
    }
}

private extension UsagePeriod {
    var label: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}

/// Today · 7 days · 30 days, in the style of the view switcher: a soft rail, the chosen period in black.
private struct PeriodSwitcher: View {
    @Binding var period: UsagePeriod
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(UsagePeriod.allCases) { p in
                let on = p == period
                Button {
                    withAnimation(.snappy(duration: 0.2)) { period = p }
                } label: {
                    Text(p.label)
                        .font(.system(size: 12, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Hive.bg : Hive.muted)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7).fill(Hive.ink)
                                    .matchedGeometryEffect(id: "on", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9).fill(Hive.soft))
    }
}

/// Output tokens per day as quiet bars, oldest on the left, today (darker) on the right.
private struct DayBars: View {
    let days: [UsageStats.Day]

    var body: some View {
        let peak = max(1, days.map(\.tokens.output).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(days.enumerated().reversed()), id: \.offset) { i, d in
                let h = d.tokens.output == 0 ? 0 : max(2, 26 * Double(d.tokens.output) / Double(peak))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i == 0 ? Hive.ink2 : Hive.hair2)
                        .frame(height: h)
                }
                .frame(maxWidth: .infinity)
                .help("\(d.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): "
                      + "\(UsageFormat.tokens(d.tokens.output)) output")
            }
        }
        .frame(height: 26)
        .background(alignment: .bottom) { Rectangle().fill(Hive.hair).frame(height: 1) }
    }
}

/// ↘ green: lasts until the reset at the current pace; → orange: gets tight; ↗ red: runs out before it.
private enum PaceArrow {
    static func text(_ pace: PlanLimits.Pace) -> Text {
        let symbol = switch pace.outlook {
        case .lasts: "arrow.down.right"
        case .tight: "arrow.right"
        case .runsOut: "arrow.up.right"
        }
        return Text(Image(systemName: symbol))
            .font(.system(size: 10.5, weight: .bold))
            .foregroundColor(pace.outlook.color)
    }

    static func sentence(_ pace: PlanLimits.Pace) -> String {
        if let t = pace.runsOutIn { return t <= 0 ? "limit reached" : "runs out in \(UsageFormat.countdown(t)) at this pace" }
        return "\(pace.outlook == .tight ? "tight" : "lasts") · about \(Int(pace.projectedPercent.rounded())) % at the reset at this pace"
    }
}

private struct LimitRow: View {
    let title: String
    let window: PlanLimits.Window
    let length: TimeInterval
    let now: Date

    var body: some View {
        let color = window.outlook(length: length, now: now)?.color
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Hive.ink)
                Spacer()
                Text("\(Int(window.percent.rounded())) %")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(color ?? Hive.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Hive.soft)
                    Capsule().fill(color ?? Hive.ink2)
                        .frame(width: max(4, geo.size.width * min(1, max(0, window.percent / 100))))
                }
            }
            .frame(height: 6)
            if let r = window.resetsAt {
                Text("resets in \(UsageFormat.countdown(r.timeIntervalSince(now)))")
                    .font(.system(size: 11.5)).foregroundStyle(Hive.muted).monospacedDigit()
            }
            if let pace = window.pace(length: length, now: now) {
                (PaceArrow.text(pace) + Text(" ") + Text(PaceArrow.sentence(pace)).foregroundColor(pace.outlook == .lasts ? Hive.muted : pace.outlook.color))
                    .font(.system(size: 11.5)).monospacedDigit()
            }
        }
    }
}

private struct TokenRow: View {
    let name: String
    let tokens: TokenCounts
    var bold = false

    var body: some View {
        HStack {
            Text(name).lineLimit(1).truncationMode(.middle).foregroundStyle(Hive.ink)
            Spacer(minLength: 8)
            Text(UsageFormat.tokens(tokens.output)).frame(width: 64, alignment: .trailing).foregroundStyle(Hive.ink)
            Text(UsageFormat.tokens(tokens.total)).frame(width: 64, alignment: .trailing).foregroundStyle(Hive.muted)
            Text(UsageFormat.usd(tokens.usd)).frame(width: 64, alignment: .trailing).foregroundStyle(Hive.ink2)
        }
        .font(.system(size: 12.5, weight: bold ? .medium : .regular))
        .monospacedDigit()
    }
}
