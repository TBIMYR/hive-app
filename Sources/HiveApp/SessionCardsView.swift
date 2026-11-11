import SwiftUI
import HiveCore

/// "Cards" view: favorites first (without a heading), below that sections by urgency like in the dashboard,
/// large cards with the "Now" box (last work step, question, or last result).
/// With the terminal on screen the cards stay slim (reading and writing happen there); with it hidden they
/// are the whole interface: questions in full, a field for a message in every running session.
struct SessionCardsView: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var dock: DockStore
    /// Favorites, already sorted (SessionOrder), including offline
    let favorites: [OverviewItem]
    /// Remaining sessions, already sorted (SessionOrder), without favorites
    let items: [OverviewItem]
    @Binding var showOffline: Bool
    /// One namespace for all sections, so a card that changes status glides from its old place to the new one
    @Namespace private var cards
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let sections: [(rank: Int, title: String, color: Color)] = [
        (0, "Needs you", Hive.need), (1, "Working", Hive.busy), (2, "Ready", Hive.idle), (3, "Offline", Hive.off),
    ]

    /// Order and section of every card; animates only when that changes, not on every clock tick
    private var layout: [String] { (favorites + items).map { "\($0.id):\($0.status.rank)" } }

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
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: layout)
    }

    private func grid(_ part: [OverviewItem]) -> some View { CardGrid(part: part, ns: cards, full: !dock.layout.isOpen(.main)) }
}

/// Grid of one section: columns of at least 360 pt; the cards of one row are as tall as the tallest of that
/// row (a long question only stretches its own row). In the full cards an open question spans as many
/// columns as come closest to a readable 760 pt.
private struct CardGrid: View {
    let part: [OverviewItem]
    let ns: Namespace.ID
    let full: Bool
    @State private var width: CGFloat = 0

    private static let minWidth: CGFloat = 360
    private static let spacing: CGFloat = 18
    private static let readable: CGFloat = 760

    var body: some View {
        let columns = max(1, Int((width + Self.spacing) / (Self.minWidth + Self.spacing)))
        let column = max(0, (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns))
        let wide = min(columns, max(1, Int(((Self.readable + Self.spacing) / (column + Self.spacing)).rounded())))
        let rows = Self.rows(part.map { ($0, full && (Self.asks($0) || $0.session.talks) ? wide : 1) }, columns: columns)
        VStack(alignment: .leading, spacing: Self.spacing) {
            ForEach(rows, id: \.first?.item.id) { row in CardRow(cells: row, columns: columns, spacing: Self.spacing, ns: ns, full: full) }
        }
        // measured on the space offered, not on the cards: their fixed widths would otherwise never let it shrink
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// An open question with options is waiting in this card
    private static func asks(_ it: OverviewItem) -> Bool {
        guard it.status.rank == 0, let line = NowLine(it.session, rank: 0) else { return false }
        return line.kind == .choice && line.question != nil
    }

    /// Cards in order, a new row when the next one no longer fits
    private static func rows(_ cells: [(item: OverviewItem, span: Int)], columns: Int) -> [[(item: OverviewItem, span: Int)]] {
        var rows: [[(item: OverviewItem, span: Int)]] = []
        var used = columns
        for c in cells {
            if used + c.span > columns { rows.append([]); used = 0 }
            rows[rows.count - 1].append(c)
            used += c.span
        }
        return rows
    }
}

/// One row of cards, equally tall; each card is as wide as its columns, empty columns stay free.
private struct CardRow: View {
    @EnvironmentObject private var store: StateStore
    let cells: [(item: OverviewItem, span: Int)]
    let columns: Int
    let spacing: CGFloat
    let ns: Namespace.ID
    let full: Bool
    @State private var tallest: CGFloat = 0

    var body: some View {
        SpanRow(spans: cells.map(\.span), columns: columns, spacing: spacing) {
            ForEach(cells, id: \.item.id) { cell in
                let it = cell.item
                let live = store.tmux(it.session) != nil
                Tile(session: it.session, status: it.status, label: it.project, color: it.color,
                     inTmux: it.inTmux, isSelected: it.name == store.selected, now: store.now,
                     isFavorite: it.isFavorite, minBody: tallest, full: full,
                     // slim cards: written in the terminal; full cards: in every running session
                     canReply: full ? live && it.status.rank != 3 : false,
                     canAnswer: it.status.rank == 0 && !it.status.core.waitsAtStart && live) {
                    store.toggleFavorite(it.name)
                }
                    .onTapGesture { store.selected = it.name }
                    .sessionMenu(store, it.session)
                    .navFrame(it.name)
                    .matchedGeometryEffect(id: it.id, in: ns)
            }
        }
        .onPreferenceChange(TallestKey.self) { tallest = $0 }
    }
}

/// Lays a row of cards out over the width it is given, `columns` equal columns, each card over its span.
/// The cards never decide the width themselves, so the grid can't grow with its own content.
private struct SpanRow: Layout {
    let spans: [Int]
    let columns: Int
    let spacing: CGFloat

    private func widths(_ total: CGFloat) -> [CGFloat] {
        let column = max(0, (total - CGFloat(columns - 1) * spacing) / CGFloat(max(1, columns)))
        return spans.map { CGFloat($0) * column + CGFloat($0 - 1) * spacing }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let height = zip(subviews, widths(width)).map { $0.sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (view, width) in zip(subviews, widths(bounds.width)) {
            view.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: .init(width: width, height: nil))
            x += width + spacing
        }
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
    /// Full card (terminal hidden): the question in full and a field for a message
    var full = false
    /// Field for a message at the bottom (full cards, running in tmux); left out while answer buttons show
    var canReply = false
    /// Answer buttons for a choice question or permission (only "needs you", in tmux, not at startup)
    var canAnswer = false
    let toggleFavorite: () -> Void

    private var isPm: Bool { session.isPm == true }
    private var show = Show()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Name and status
                HStack(spacing: 8) {
                    if isPm { Token(text: session.abbr, color: color) }
                    Text(session.name).font(.hive(size: 18, weight: .semibold)).foregroundStyle(Hive.ink).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    if status.cls == "off" {
                        WakeUpButton(session: session)
                    } else if show.status || show.since {
                        CardStatus(status: status, since: show.since && session.alive == true ? dur(session.statusUpdatedAt, now: now) : "",
                                   text: show.status ? nil : "")
                            .layoutPriority(-1)
                    }
                    if show.badges {
                        RemoteControlBadge(on: session.remoteControl)
                        BackgroundBadge(count: session.backgroundTasks)
                    }
                    if show.load { LoadBadge(session: session) }
                    if show.badges { NoteBadge(name: session.name) }
                    StarButton(isOn: isFavorite, toggle: toggleFavorite)
                        .padding(.trailing, -4)
                }

                if show.context {
                    ContextLine(percent: session.contextPercent)
                        .padding(.top, 12)
                }

                let line = NowLine(session, rank: status.rank)

                // task: gray if it's noticeably older than the last activity
                let outdated = session.taskOutdated
                Text(session.task?.text ?? "No task line")
                    .font(.hive(size: 15, weight: session.task?.text == nil || outdated ? .medium : .semibold))
                    .foregroundStyle(session.task?.text == nil || outdated ? Hive.muted : Hive.ink)
                    .lineLimit(2, reservesSpace: !show.detail || session.task?.detail == nil)
                    .padding(.top, 12)
                if show.detail, let detail = session.task?.detail {
                    Text(detail).font(.hive(size: 13)).foregroundStyle(Hive.muted).lineLimit(2)
                        .padding(.top, 3)
                }

                // always two lines high, so plain cards are equally tall; without a "Now" line the reason (if any)
                // in the status color
                // hidden: only an open question keeps its box, for the answer buttons
                // an open choice or approval keeps its buttons; otherwise a full card shows the conversation
                let buttons = canAnswer && (line?.kind == .permission || line?.kind == .choice)
                if show.now || canAnswer || full {
                    Group {
                        if full && !buttons && session.talks {
                            CardConversation(session: session, working: status.rank == 1, now: now)
                        } else if let line {
                            NowBox(line: line, now: now, answerFor: canAnswer ? session : nil, full: full)
                        } else {
                            NowSlot {
                                if let why = status.why {
                                    Text(why).font(.hive(size: 13, weight: .medium)).foregroundStyle(status.color).lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }

                // an open choice or approval is answered with its buttons; the field would type into the dialog
                if canReply && !buttons {
                    ReplyField(session: session).padding(.top, 12)
                }
            }
            .matchTallest(minBody)

            // Meta: project · branch, on the right where the session runs
            HStack(spacing: 6) {
                if show.project {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label)
                    if let b = session.branch, b != "HEAD" {
                        Text("·")
                        Text(b).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 6)
                if show.model, let m = session.model {
                    Text(ModelName.short(m)).fixedSize().help(m)
                }
                if !session.errors.isEmpty {
                    Image(systemName: "exclamationmark.triangle")
                        .help("Read error: " + session.errors.joined(separator: "\n"))
                }
                if show.place {
                    if inTmux {
                        Image(systemName: "terminal").help("Runs in the app")
                    } else if session.alive == true && session.kind != "bg" {
                        Text("iTerm").fixedSize()
                    }
                }
            }
            .lineLimit(1)
            .font(.hive(size: 12))
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
    /// Full card: the question in full with the options' descriptions and a field for own words
    var full = false

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
            // the reading view of a question takes the whole width
            if !(line.kind == .choice && line.question != nil) {
                Image(systemName: icon)
                    .font(.hive(size: 12, weight: .medium))
                    .foregroundStyle(Hive.muted)
                    .frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 4) {
                let since = line.kind == .working ? dur(line.at, now: now) : ""
                let hasDetail = line.detail != nil || !since.isEmpty
                // text and detail line take two lines; without a detail line the text may use both
                if line.kind == .choice, let q = line.question {
                    QuestionReader(question: q, line: line, answerFor: answerFor, full: full)
                } else {
                NowSlot {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.text)
                            .font(.hive(size: 14, weight: line.kind == .permission ? .semibold : .regular))
                            .foregroundStyle(line.kind == .permission ? Hive.ink : Hive.ink2)
                            // an open question with options is shown whole, otherwise it can't be answered
                            .lineLimit(line.kind == .choice ? nil : hasDetail ? 1 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                        if hasDetail {
                            HStack(spacing: 5) {
                                if let d = line.detail { CodeChip(text: d) }
                                if !since.isEmpty { Text(line.detail == nil ? since : "· \(since)").fixedSize() }
                            }
                            .font(.hive(size: 12)).foregroundStyle(Hive.muted).lineLimit(1)
                        }
                    }
                }
                if buttons, let s = answerFor {
                    AnswerButtons(session: s, line: line).padding(.top, 4)
                } else if line.kind == .choice {
                    ForEach(Array(line.options.enumerated()), id: \.offset) { i, o in
                        Text("\(i + 1) · \(o)").lineLimit(1)
                    }
                    .font(.hive(size: 12)).foregroundStyle(Hive.muted)
                    TerminalHint(session: answerFor).padding(.top, 2)
                }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// An open question with options, readable: paragraphs, list items on their own lines, the question itself set
/// apart. Folded it shows the start and the question; "Show all" opens the whole text and the options with
/// their descriptions. Slim (terminal on screen) it shows only the question and the buttons; the text is in
/// the terminal.
struct QuestionReader: View {
    let question: AskedQuestion
    let line: NowLine
    var answerFor: Session?
    var full = true
    @State private var open = true

    private var blocks: [QuestionText.Block] { QuestionText.blocks(question.text) }

    var body: some View {
        let blocks = blocks
        let ask = blocks.last.flatMap { if case .ask(let a) = $0 { a } else { nil } }
        let body = !full && ask != nil ? [] : ask == nil ? blocks : Array(blocks.dropLast())
        let open = open && full
        VStack(alignment: .leading, spacing: 12) {
            // the question itself on a sheet of its own, set off from the card
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    if let h = question.header {
                        Text(h).font(.hive(size: 11, weight: .semibold)).foregroundStyle(Hive.muted).textCase(.uppercase)
                    }
                    Spacer(minLength: 8)
                    if full && (body.count > 1 || !open && !body.isEmpty) {
                        Button(open ? "Show less" : "Show all") { withAnimation(.easeOut(duration: 0.15)) { self.open.toggle() } }
                            .buttonStyle(.link).font(.hive(size: 12, weight: .medium))
                    }
                }
                if open {
                    ForEach(Array(body.enumerated()), id: \.offset) { _, b in block(b) }
                } else if let first = body.first {
                    block(first).lineLimit(2)
                }
                if let ask {
                    Text(Self.md(ask)).font(.hive(size: 15, weight: .semibold)).foregroundStyle(Hive.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, body.isEmpty ? 0 : 4)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Hive.well))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Hive.hair2, lineWidth: 1))
            if let s = answerFor, line.singleChoice {
                AnswerButtons(session: s, line: line, descriptions: open ? question.options : nil).padding(.top, 2)
            } else {
                ForEach(Array(question.options.enumerated()), id: \.offset) { i, o in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(i + 1) · \(o.label)").font(.hive(size: 13, weight: .medium)).foregroundStyle(Hive.ink2)
                        if open, let d = o.description {
                            Text(Self.md(d)).font(.hive(size: 12.5)).foregroundStyle(Hive.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                TerminalHint(session: answerFor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: question) { self.open = true }
    }

    @ViewBuilder private func block(_ b: QuestionText.Block) -> some View {
        switch b {
        case .paragraph(let p), .ask(let p):
            Text(Self.md(p)).font(.hive(size: 14)).foregroundStyle(Hive.ink2)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: !open ? false : true)
        case .item(let marker, let title, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).font(.hiveMono(12)).foregroundStyle(Hive.muted).frame(minWidth: 14, alignment: .trailing)
                (Text(title.map { Self.md($0 + " ") } ?? "").fontWeight(.semibold).foregroundColor(Hive.ink)
                 + Text(Self.md(text)).foregroundColor(Hive.ink2))
                    .font(.hive(size: 14)).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: open)
            }
        }
    }

    /// inline Markdown (**bold**, `code`) as the session wrote it
    static func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// "Answer in the terminal" for what the buttons can't answer (several questions, multiple choice)
struct TerminalHint: View {
    let session: Session?

    var body: some View {
        HStack(spacing: 8) {
            Text("Answer in the terminal").foregroundStyle(Hive.ink2)
            if let session { ShowTerminal(session: session) }
        }
        .font(.hive(size: 12, weight: .medium))
    }
}

/// With the terminal folded away: a link that opens it on this session, instead of sending the user there.
struct ShowTerminal: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var dock: DockStore
    let session: Session

    var body: some View {
        if !dock.layout.isOpen(.main) {
            Button("Show terminal") {
                store.selected = session.name
                dock.change { $0.setCollapsed(false, groupOf: .main); $0.select(.main) }
            }
            .buttonStyle(.link)
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
                Text(" ").font(.hive(size: 14))
                CodeChip(text: " ").font(.hive(size: 12))
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
    /// the options with their descriptions: one wide button each (the opened reading view)
    var descriptions: [AskedQuestion.Option]? = nil
    @State private var ownWords = ""
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
            Group {
                if let descriptions {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(descriptions.enumerated()), id: \.offset) { _, o in
                            Button { send(.option(o.label)) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(o.label).font(.hive(size: 14, weight: .semibold)).foregroundStyle(Hive.ink)
                                    if let d = o.description {
                                        Text(QuestionReader.md(d)).font(.hive(size: 12.5)).foregroundStyle(Hive.ink2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(OptionCardStyle())
                        }
                        // Claude Code's own "Type something." line
                        HStack(spacing: 6) {
                            TextField("Or in your own words…", text: $ownWords)
                                .textFieldStyle(.plain).font(.hive(size: 14))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(RoundedRectangle(cornerRadius: 9).fill(Hive.card))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Hive.hair2, lineWidth: 1))
                                .onSubmit(sendOwnWords)
                            Button("Send", action: sendOwnWords)
                                .buttonStyle(AnswerButtonStyle(primary: true))
                                .disabled(ownWords.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(choices) { c in
                            Button(c.id) { send(c.answer) }
                                .buttonStyle(AnswerButtonStyle(primary: c.primary))
                        }
                    }
                }
            }
            .disabled(sending || typing)
            .help(typing ? "You are typing in this terminal – wait a moment" : "")
            if let note {
                HStack(spacing: 8) {
                    Text(note).font(.hive(size: 11.5)).foregroundStyle(note == Tmux.noDialog ? Hive.muted : Hive.need).lineLimit(2)
                    // with the terminal folded away, open it instead of sending the user to it
                    if note != Tmux.noDialog { ShowTerminal(session: session).font(.hive(size: 11.5, weight: .medium)) }
                }
            }
        }
        .task(id: line) {
            note = nil
            guard line.kind == .permission else { return }
            hasAlways = await store.dialog(session)?.permission(.alwaysAllow) != nil
        }
    }

    private func sendOwnWords() {
        let words = ownWords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        send(.text(words.replacingOccurrences(of: "\n", with: " ")))
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
            .font(.hive(size: 14, weight: .medium))
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

/// An option with its description as one wide button (reading view).
struct OptionCardStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(configuration.isPressed ? Hive.bg : Hive.card)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Hive.hair2, lineWidth: 1))
            .opacity(enabled ? 1 : 0.4)
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
            .font(.hive(size: 12, weight: .medium))
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
                .font(.hive(size: 13))
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
                Text(error).font(.hive(size: 11.5)).foregroundStyle(Hive.need).lineLimit(2)
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

/// How full the session's context window is: a thin line under the name, on a faint track so every card
/// keeps the same height. Orange from 80 %, red from 90 % (time for a handover and /clear).
struct ContextLine: View {
    let percent: Double?

    static func color(_ p: Double) -> Color { p >= 90 ? Hive.need : p >= 80 ? Hive.block : Hive.busy }
    static func help(_ percent: Double?) -> String {
        percent.map { "Context \(Int($0.rounded())) % used" } ?? "Context usage unknown"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Hive.soft)
                if let p = percent, p > 0 {
                    Capsule().fill(Self.color(p)).frame(width: max(3, geo.size.width * p / 100))
                }
            }
        }
        .frame(height: 3)
        .help(Self.help(percent))
    }
}

/// Context usage for the tiles: a 2 pt line along the bottom edge, clipped by the tile's rounded corners.
struct ContextEdge: View {
    let percent: Double?
    let radius: CGFloat

    var body: some View {
        GeometryReader { geo in
            if let p = percent, p > 0 {
                Rectangle().fill(ContextLine.color(p))
                    .frame(width: geo.size.width * p / 100, height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .allowsHitTesting(false)
    }
}

/// Context usage for the list rows: the status dot with a thin ring around it that fills clockwise.
struct ContextDot: View {
    let color: Color
    let percent: Double?

    var body: some View {
        ZStack {
            Circle().stroke(Hive.soft, lineWidth: 1.5)
            if let p = percent, p > 0 {
                Circle().trim(from: 0, to: p / 100)
                    .stroke(ContextLine.color(p), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle().fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 15, height: 15)
        .help(ContextLine.help(percent))
    }
}

extension Session {
    /// Has a conversation to show in a full card: running, with a message or an answer
    var talks: Bool { alive && (answer != nil || lastUser != nil) }
}
