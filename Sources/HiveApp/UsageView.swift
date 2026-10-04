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
        // transcripts change all the time: at most one scan per 10 s from events
        transcriptWatcher = Watcher(paths: ["\(home)/projects"], delay: 10) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        // ~/.claude.json is not watched (its folder is the home folder): the timer picks it up
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadLimits()
                self?.rescan()
            }
        }
    }

    func current(now: Date) -> PlanLimits? { limits?.droppingExpired(now: now) }

    func reloadLimits() {
        queue.async { [weak self] in
            let l = PlanLimits.load()
            Task { @MainActor in if self?.limits != l { self?.limits = l } }
        }
    }

    func rescan() {
        guard !scanning else { return }
        scanning = true
        let scanner = scanner
        queue.async { [weak self] in
            let s = scanner.scan()
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                if self.stats != s { self.stats = s }
            }
        }
    }
}

private extension UsageFormat.Level {
    var color: Color {
        switch self {
        case .normal: Hive.ink2
        case .warning: Hive.block
        case .critical: Hive.need
        }
    }
}

/// Title bar: "5h 19% (2h 14m) · Week 78% (1d 3h)"; click opens the details.
struct UsageButton: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: StateStore
    @State private var open = false

    var body: some View {
        let now = store.now
        if let limits = usage.current(now: now) {
            Button { open.toggle() } label: { label(limits, now: now) }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .help("Plan usage")
                .popover(isPresented: $open, arrowEdge: .bottom) { UsagePopover() }
        }
    }

    private func label(_ l: PlanLimits, now: Date) -> some View {
        var parts: [Text] = []
        if let w = l.fiveHour { parts.append(part("5h", w, now: now)) }
        if let w = l.sevenDay { parts.append(part("Week", w, now: now)) }
        if parts.isEmpty, let s = l.scoped.first { parts.append(part(s.name, s.window, now: now)) }
        let joined = parts.dropFirst().reduce(parts.first ?? Text("")) { a, b in
            a + Text("  ·  ").foregroundColor(Hive.hair2) + b
        }
        return joined.font(.system(size: 12.5, weight: .medium)).monospacedDigit().lineLimit(1).fixedSize()
    }

    private func part(_ name: String, _ w: PlanLimits.Window, now: Date) -> Text {
        let main = Text("\(name) \(Int(w.percent.rounded()))%").foregroundColor(UsageFormat.level(w.percent).color)
        guard let r = w.resetsAt else { return main }
        return main + Text(" (\(UsageFormat.countdown(r.timeIntervalSince(now))))")
            .font(.system(size: 11)).foregroundColor(Hive.muted)
    }
}

/// Details: both limits with bars and countdown, source, then tokens today and over the week.
struct UsagePopover: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: StateStore

    var body: some View {
        let now = store.now
        VStack(alignment: .leading, spacing: 16) {
            if let l = usage.current(now: now) {
                VStack(alignment: .leading, spacing: 14) {
                    if let w = l.fiveHour { LimitRow(title: "Session (5 hours)", window: w, now: now) }
                    if let w = l.sevenDay { LimitRow(title: "Week", window: w, now: now) }
                    ForEach(l.scoped, id: \.name) { s in LimitRow(title: "Week · \(s.name)", window: s.window, now: now) }
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
            }
            .font(.system(size: 11.5)).foregroundStyle(Hive.muted)
            TokenRow(name: "Today", tokens: s.today, bold: true)
            TokenRow(name: "Last 7 days", tokens: s.last7Days, bold: true)
            Text(cacheNote(s)).font(.system(size: 11.5)).foregroundStyle(Hive.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !s.projectsToday.isEmpty {
            section("Top projects today", s.projectsToday)
        }
        if !s.sessionsToday.isEmpty {
            section("Top sessions today", s.sessionsToday)
        }
    }

    private func cacheNote(_ s: UsageStats) -> String {
        let t = s.last7Days
        guard t.total > 0 else { return "Total includes cache reads." }
        let share = Int((Double(t.cacheRead) / Double(t.total) * 100).rounded())
        return "Total includes cache reads (\(share) % of the week)."
    }

    private func section(_ title: String, _ rows: [UsageStats.Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
            ForEach(rows.prefix(5)) { r in TokenRow(name: r.name, tokens: r.tokens) }
        }
    }
}

private struct LimitRow: View {
    let title: String
    let window: PlanLimits.Window
    let now: Date

    var body: some View {
        let level = UsageFormat.level(window.percent)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Hive.ink)
                Spacer()
                Text("\(Int(window.percent.rounded())) %")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(level == .normal ? Hive.ink : level.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Hive.soft)
                    Capsule().fill(level == .normal ? Hive.ink2 : level.color)
                        .frame(width: max(4, geo.size.width * min(1, max(0, window.percent / 100))))
                }
            }
            .frame(height: 6)
            if let r = window.resetsAt {
                Text("resets in \(UsageFormat.countdown(r.timeIntervalSince(now)))")
                    .font(.system(size: 11.5)).foregroundStyle(Hive.muted).monospacedDigit()
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
        }
        .font(.system(size: 12.5, weight: bold ? .medium : .regular))
        .monospacedDigit()
    }
}
