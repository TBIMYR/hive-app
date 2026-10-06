import SwiftUI
import HiveCore

/// "Cards" view: favorites first (without a heading), below that sections by urgency like in the dashboard,
/// large cards with the "Now" box (last work step, question, or last result).
struct SessionCardsView: View {
    @EnvironmentObject private var store: StateStore
    /// Favorites, already sorted (SessionOrder), including offline
    let favorites: [OverviewItem]
    /// Remaining sessions, already sorted (SessionOrder), without favorites
    let items: [OverviewItem]
    @Binding var showOffline: Bool

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Needs you", Hive.need), (1, "Working", Hive.busy), (2, "Ready", Hive.idle), (3, "Offline", Hive.off),
    ]

    var body: some View {
        // PMs have no section of their own among the remaining cards; they stand out by the project chip next to the name (Tile)
        VStack(alignment: .leading, spacing: 34) {
            if !favorites.isEmpty { grid(favorites) }
            ForEach(Self.sections, id: \.rank) { sec in
                let part = items.filter { $0.status.rank == sec.rank }
                if !part.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: sec.title, count: part.count, color: sec.color,
                                      expanded: sec.rank == 3 ? $showOffline : nil)
                        if sec.rank != 3 || showOffline { grid(part) }
                    }
                }
            }
        }
    }

    private func grid(_ part: [OverviewItem]) -> some View { CardGrid(part: part) }
}

/// Grid of one section: columns of at least 360 pt; the cards of one row are as tall as the tallest of that
/// row (a long question only stretches its own row).
private struct CardGrid: View {
    let part: [OverviewItem]
    @State private var width: CGFloat = 0

    private static let minWidth: CGFloat = 360
    private static let spacing: CGFloat = 18

    var body: some View {
        let columns = max(1, Int((width + Self.spacing) / (Self.minWidth + Self.spacing)))
        let rows = stride(from: 0, to: part.count, by: columns).map { Array(part[$0..<min($0 + columns, part.count)]) }
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(rows, id: \.first?.id) { row in CardRow(items: row, columns: columns, spacing: Self.spacing) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// One row of cards, equally tall; empty columns stay free so all cards keep the same width.
private struct CardRow: View {
    @EnvironmentObject private var store: StateStore
    let items: [OverviewItem]
    let columns: Int
    let spacing: CGFloat
    @State private var tallest: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items) { it in
                Tile(session: it.session, status: it.status, label: it.project, color: it.color,
                     inTmux: it.inTmux, isSelected: it.name == store.selected, now: store.now,
                     isFavorite: it.isFavorite, minBody: tallest,
                     canReply: it.status.rank == 0 && it.session.acceptsReply && store.tmux(it.session) != nil,
                     canAnswer: it.status.rank == 0 && !it.status.core.waitsAtStart && store.tmux(it.session) != nil) {
                    store.toggleFavorite(it.name)
                }
                    .onTapGesture { store.selected = it.name }
                    .sessionMenu(store, it.session)
                    .navFrame(it.name)
            }
            ForEach(items.count..<columns, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
        }
        .onPreferenceChange(TallestKey.self) { tallest = $0 }
    }
}

struct Tile: View {
    let session: Session
    let status: Status
    let label: String
    let color: Color
    let inTmux: Bool
    let isSelected: Bool
    let now: Date
    let isFavorite: Bool
    /// Height of the tallest card body in the section (everything above the footer); this body grows to it
    var minBody: CGFloat = 0
    /// Reply field at the bottom (only "needs you", in tmux, and without an open choice dialog)
    var canReply = false
    /// Answer buttons for a choice question or permission (only "needs you", in tmux, not at startup)
    var canAnswer = false
    let toggleFavorite: () -> Void

    private var isPm: Bool { session.isPm == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Name and status
                HStack(spacing: 8) {
                    if isPm { Token(text: session.abbr, color: color) }
                    Text(session.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Hive.ink).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    if status.cls == "off" {
                        WakeUpButton(session: session)
                    } else {
                        CardStatus(status: status, since: session.alive == true ? dur(session.statusUpdatedAt, now: now) : "")
                            .layoutPriority(-1)
                    }
                    BackgroundBadge(count: session.backgroundTasks)
                    StarButton(isOn: isFavorite, toggle: toggleFavorite)
                        .padding(.trailing, -4)
                }

                let line = NowLine(session, rank: status.rank)

                // task: gray if it's noticeably older than the last activity
                let outdated = session.taskOutdated
                Text(session.task?.text ?? "No task line")
                    .font(.system(size: 15, weight: session.task?.text == nil || outdated ? .medium : .semibold))
                    .foregroundStyle(session.task?.text == nil || outdated ? Hive.muted : Hive.ink)
                    .lineLimit(2, reservesSpace: true)
                    .padding(.top, 14)

                // always two lines high, so plain cards are equally tall; without a "Now" line the reason (if any)
                // in the status color
                Group {
                    if let line {
                        NowBox(line: line, now: now, answerFor: canAnswer ? session : nil)
                    } else {
                        NowSlot {
                            if let why = status.why {
                                Text(why).font(.system(size: 13, weight: .medium)).foregroundStyle(status.color).lineLimit(2)
                            }
                        }
                    }
                }
                .padding(.top, 10)

                if canReply { ReplyField(session: session).padding(.top, 12) }
            }
            .matchTallest(minBody)

            // Meta: project · branch, on the right where the session runs
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                if let b = session.branch, b != "HEAD" {
                    Text("·")
                    Text(b).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if !session.errors.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .help("Read error: " + session.errors.joined(separator: "\n"))
                }
                if inTmux {
                    Image(systemName: "terminal").help("Runs in the app")
                } else if session.alive == true && session.kind != "bg" {
                    Text("iTerm").fixedSize()
                }
            }
            .lineLimit(1)
            .font(.system(size: 12))
            .foregroundStyle(Hive.muted)
            .padding(.top, 16)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(status: status, isSelected: isSelected)
        .opacity(status.rank == 3 ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

/// "Now" line: when working, the last work step; when waiting, a permission or question; when ready, the last sentence.
/// Plain icon and text without a box, so the card stays calm.
struct NowBox: View {
    let line: NowLine
    let now: Date
    /// Session that can be answered via button; nil = no buttons
    var answerFor: Session? = nil

    private var icon: String {
        switch line.kind {
        case .working: "gearshape"
        case .permission: "lock"
        case .question, .choice: "questionmark.bubble"
        case .done: "checkmark"
        }
    }

    /// Buttons instead of a list: a permission, or a single question without multiple choice
    private var buttons: Bool {
        answerFor != nil && (line.kind == .permission || (line.kind == .choice && line.singleChoice))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Hive.muted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                let since = line.kind == .working ? dur(line.at, now: now) : ""
                let hasDetail = line.detail != nil || !since.isEmpty
                // text and detail line take two lines; without a detail line the text may use both
                NowSlot {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.text)
                            .font(.system(size: 13, weight: line.kind == .permission ? .semibold : .regular))
                            .foregroundStyle(line.kind == .permission ? Hive.ink : Hive.ink2)
                            // an open question with options is shown whole, otherwise it can't be answered
                            .lineLimit(line.kind == .choice ? nil : hasDetail ? 1 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if hasDetail {
                            HStack(spacing: 5) {
                                if let d = line.detail { CodeChip(text: d) }
                                if !since.isEmpty { Text(line.detail == nil ? since : "· \(since)").fixedSize() }
                            }
                            .font(.system(size: 12)).foregroundStyle(Hive.muted).lineLimit(1)
                        }
                    }
                }
                if buttons, let s = answerFor {
                    AnswerButtons(session: s, line: line).padding(.top, 4)
                } else if line.kind == .choice {
                    ForEach(Array(line.options.enumerated()), id: \.offset) { i, o in
                        Text("\(i + 1) · \(o)").lineLimit(1)
                    }
                    .font(.system(size: 12)).foregroundStyle(Hive.muted)
                    Text("Answer in the terminal").font(.system(size: 12, weight: .medium)).foregroundStyle(Hive.ink2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Reserves the height of a "Now" line plus its detail line, so cards with less to say are just as tall.
/// The content sits on top.
struct NowSlot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(" ").font(.system(size: 13))
                CodeChip(text: " ").font(.system(size: 12))
            }
            .hidden()
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Answer buttons in the "Now" box: one per option of a choice question, or Allow/Always allow/Deny for a
/// permission. A click checks the screen and types the digit (Tmux.answer); never automatically.
/// Disabled while someone is typing into this session's terminal.
struct AnswerButtons: View {
    @EnvironmentObject private var store: StateStore
    @ObservedObject private var activity = TerminalActivity.shared
    let session: Session
    let line: NowLine
    @State private var sending = false
    @State private var note: String?
    /// "Always allow" is on the screen (read once, when the permission appears)
    @State private var hasAlways = false

    private struct Choice: Identifiable {
        let id: String
        let answer: ScreenDialog.Answer
        let primary: Bool
    }

    private var choices: [Choice] {
        if line.kind == .permission {
            var c = [Choice(id: "Allow", answer: .permission(.allow), primary: true)]
            if hasAlways { c.append(Choice(id: "Always allow", answer: .permission(.alwaysAllow), primary: false)) }
            c.append(Choice(id: "Deny", answer: .permission(.deny), primary: false))
            return c
        }
        return line.options.map { Choice(id: $0, answer: .option($0), primary: false) }
    }

    private var typing: Bool { activity.typingIn != nil && activity.typingIn == store.tmux(session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FlowLayout(spacing: 6) {
                ForEach(choices) { c in
                    Button(c.id) { send(c.answer) }
                        .buttonStyle(AnswerButtonStyle(primary: c.primary))
                }
            }
            .disabled(sending || typing)
            .help(typing ? "You are typing in this terminal – wait a moment" : "")
            if let note {
                Text(note).font(.system(size: 11.5)).foregroundStyle(Hive.need).lineLimit(2)
            }
        }
        .task(id: line) {
            note = nil
            guard line.kind == .permission else { return }
            hasAlways = await store.dialog(session)?.permission(.alwaysAllow) != nil
        }
    }

    private func send(_ answer: ScreenDialog.Answer) {
        guard !sending else { return }
        sending = true
        note = nil
        Task {
            note = await store.answer(answer, known: line.options, to: session)
            sending = false
        }
    }
}

/// Small button in the Hive style: "Allow" filled dark, otherwise light with a border.
struct AnswerButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .lineLimit(2).multilineTextAlignment(.leading)
            .foregroundStyle(primary ? Hive.card : Hive.ink)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(primary ? Hive.ink : Hive.card)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(primary ? Color.clear : Hive.hair2, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}

/// Small "Wake Up" button in place of the "offline" status (cards, tiles, list).
struct WakeUpButton: View {
    @EnvironmentObject private var store: StateStore
    let session: Session

    var body: some View {
        Button("Wake Up") { store.wakeUp(session) }
            .buttonStyle(WakeButtonStyle())
            .help("Start claude -n \(session.name) in Hive; it reads its handover")
            .fixedSize()
    }
}

struct WakeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Hive.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Hive.card)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Hive.hair2, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// Command or path in monospace font on a gray background.
struct CodeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.hiveMono(12))
            .foregroundStyle(Hive.ink2)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Hive.hair)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Single-line reply field in waiting cards: Enter types the text into the session via tmux.
/// A click into the field only grabs focus; the card doesn't get selected (otherwise the
/// terminal of the selection would immediately take the focus back).
struct ReplyField: View {
    @EnvironmentObject private var store: StateStore
    let session: Session
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("", text: $text, prompt: Text("Reply…").foregroundColor(Hive.muted))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Hive.ink)
                .focused($focused)
                .disabled(sending)
                .onSubmit(send)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Hive.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? Hive.hair2 : Hive.hair, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .onChange(of: text) { error = nil }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Hive.need).lineLimit(2)
            }
        }
    }

    private func send() {
        guard SessionControl.replyText(text) != nil, !sending else { return }
        sending = true
        let sent = text
        Task {
            if let e = await store.reply(sent, to: session) {
                error = "Not sent: \(e)"
            } else {
                text = ""
            }
            sending = false
            focused = true
        }
    }
}
