import AppKit
import SwiftUI
import HiveCore

/// Notes per session from `~/.claude/hive/notes/<session>/` (to try it out: `HIVE_NOTES=<path>`).
/// Picks up notes written from outside (`cc-note`) through the watcher. Where each note card sits in
/// the window is kept in the user defaults (`noteFrames`), not in the note files.
@MainActor
final class NotesStore: ObservableObject {
    /// Number of notes per session name, for the badges
    @Published private(set) var counts: [String: Int] = [:]
    /// Notes of the session shown in the window, newest first
    @Published private(set) var notes: [Note] = []
    /// Position and size per note ("session/id" → x, y, width, height); missing = not placed yet
    @Published private(set) var frames: [String: CGRect] = [:]
    /// Note that should take the keyboard focus (a fresh one)
    @Published var focusRequest: String?
    private(set) var session: String?
    let root = Notes.root()
    private var watcher: Watcher?

    private static let framesKey = "noteFrames"

    init() {
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let stored = UserDefaults.standard.dictionary(forKey: Self.framesKey) as? [String: [Double]] ?? [:]
        frames = stored.compactMapValues { $0.count == 4 ? CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) : nil }
        load()
        watcher = Watcher(paths: [root]) { [weak self] in
            Task { @MainActor in self?.load() }
        }
    }

    /// The window shows this session's notes from now on.
    func show(_ name: String?) {
        guard name != session else { return }
        session = name
        load()
    }

    func load() {
        let c = Notes.counts(root: root)
        if c != counts { counts = c }
        let n = session.map { Notes.list(root: root, session: $0) } ?? []
        if n != notes { notes = n }
    }

    /// A new note on `session` (blank or with text); it takes the focus when blank.
    func add(to session: String, text: String = "") {
        guard let note = Notes.add(root: root, session: session, text: text) else { return }
        if text.isEmpty { focusRequest = note.id }
        load()
    }

    func save(_ id: String, _ text: String) {
        guard let session else { return }
        Notes.save(root: root, session: session, id: id, text: text)
        load()
    }

    func remove(_ id: String) {
        guard let session else { return }
        Notes.remove(root: root, session: session, id: id)
        frames[key(id)] = nil
        persistFrames()
        load()
    }

    /// The session's recent answers, to pick one for a note.
    func recentReplies(of name: String) async -> [Said] {
        await Task.detached { Notes.recentReplies(session: name) }.value
    }

    // MARK: Frames

    private func key(_ id: String) -> String { "\(session ?? "")/\(id)" }

    func frame(_ id: String) -> CGRect? { frames[key(id)] }

    /// While dragging: only in memory; `persistFrames()` when the gesture ends.
    func setFrame(_ id: String, _ frame: CGRect) { frames[key(id)] = frame }

    func persistFrames() {
        let plain = frames.mapValues { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
        UserDefaults.standard.set(plain, forKey: Self.framesKey)
    }
}

/// Small note icon with the count for sessions that have notes; nothing otherwise.
struct NoteBadge: View {
    let name: String
    @EnvironmentObject private var notes: NotesStore

    var body: some View {
        if let n = notes.counts[name] {
            HStack(spacing: 3) {
                Image(systemName: "note.text").font(.system(size: 10.5, weight: .semibold))
                Text("\(n)").font(.system(size: 12)).monospacedDigit()
            }
            .foregroundStyle(Hive.muted)
            .fixedSize()
            .help(n == 1 ? "1 note (⌘T)" : "\(n) notes (⌘T)")
        }
    }
}

/// The notes of the selected session as separate cards floating in the Hive window.
struct NotesLayer: View {
    @EnvironmentObject private var notes: NotesStore
    /// Selected session (name), nil = none
    let session: String?
    /// Window size the cards must fit into
    let bounds: CGSize
    /// Where the first card of a session goes; the next ones step down and to the left
    let defaultOrigin: CGPoint
    /// Card clicked last, drawn on top
    @State private var front: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // oldest first, so a new note lands on top
            ForEach(Array(notes.notes.reversed().enumerated()), id: \.element.id) { i, note in
                NoteCard(note: note, bounds: bounds, fallbackOrigin: fallback(i), bringToFront: { front = note.id })
                    .zIndex(front == note.id ? 1 : 0)
            }
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .onAppear { notes.show(session) }
        .onChange(of: session) { _, new in notes.show(new) }
        .onChange(of: notes.focusRequest) { _, new in if let new { front = new } }
    }

    private func fallback(_ i: Int) -> CGPoint {
        let step = CGFloat(i % 8) * 28
        return CGPoint(x: defaultOrigin.x - step, y: defaultOrigin.y + step)
    }
}

/// One note: a plain card without a header. Its text is always editable and looks like rendered Markdown
/// (see NoteEditor). Drag it by its top margin, resize it by the grip.
struct NoteCard: View {
    @EnvironmentObject private var notes: NotesStore
    let note: Note
    let bounds: CGSize
    let fallbackOrigin: CGPoint
    let bringToFront: () -> Void

    @State private var text = ""
    @State private var dragStart: CGRect?
    @State private var resizeStart: CGRect?
    @State private var copied = false
    @State private var confirmDelete = false
    @State private var hovering = false
    /// the cursor is in this note
    @State private var focused = false

    static let minSize = CGSize(width: 180, height: 120)
    static let defaultSize = CGSize(width: 300, height: 220)

    /// Stored frame (or the default), kept inside the window without changing the stored value.
    private var frame: CGRect {
        let f = notes.frame(note.id) ?? CGRect(origin: fallbackOrigin, size: Self.defaultSize)
        let w = min(max(f.width, Self.minSize.width), max(Self.minSize.width, bounds.width)).rounded()
        let h = min(max(f.height, Self.minSize.height), max(Self.minSize.height, bounds.height)).rounded()
        return CGRect(x: min(max(f.minX, 0), max(0, bounds.width - w)).rounded(),
                      y: min(max(f.minY, 0), max(0, bounds.height - h)).rounded(), width: w, height: h)
    }

    var body: some View {
        let f = frame
        VStack(spacing: 0) {
            handle
            NoteEditor(text: $text, wantsFocus: notes.focusRequest == note.id) { now in
                focused = now
                if now {
                    bringToFront()
                    if notes.focusRequest == note.id { notes.focusRequest = nil }
                }
            }
            .padding(.bottom, 10)
        }
        .frame(width: f.width, height: f.height)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Hive.hair, lineWidth: 1))
        .overlay(alignment: .bottomTrailing) { resizeGrip }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .offset(x: f.minX, y: f.minY)
        .onHover { hovering = $0 }
        .simultaneousGesture(TapGesture().onEnded { bringToFront() })
        .onAppear { text = note.text }
        // changed from outside (cc-note, another window): take it over unless the user is typing here
        .onChange(of: note.text) { _, new in if !focused { text = new } }
        .onChange(of: text) { _, new in
            if new.trimmingCharacters(in: .whitespacesAndNewlines) != note.text { notes.save(note.id, new) }
        }
    }

    /// Blank margin on top to drag the card by; copy and delete appear on its right while hovering.
    private var handle: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 4)
            if hovering || confirmDelete || copied {
                if confirmDelete {
                    Button("Delete?") { notes.remove(note.id) }
                        .buttonStyle(.plain).foregroundStyle(Hive.need).fontWeight(.semibold)
                        .help("Click again to delete this note")
                } else {
                    iconButton(copied ? "checkmark" : "doc.on.doc", "Copy the text") { copy() }
                    iconButton("trash", "Delete") { askDelete() }
                }
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(Hive.muted)
        .padding(.trailing, 12).frame(height: 34)
        .contentShape(Rectangle())
        .help("Drag to move")
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    let start = dragStart ?? frame
                    if dragStart == nil { bringToFront() }
                    dragStart = start
                    notes.setFrame(note.id, CGRect(x: (start.minX + v.translation.width).rounded(),
                                                   y: (start.minY + v.translation.height).rounded(),
                                                   width: start.width, height: start.height))
                }
                .onEnded { _ in
                    // what's stored is where the card actually ends up
                    notes.setFrame(note.id, frame)
                    notes.persistFrames()
                    dragStart = nil
                }
        )
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12.5, weight: .semibold)).frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var resizeGrip: some View {
        Color.clear
            .overlay(alignment: .bottomTrailing) {
                Path { p in
                    p.move(to: CGPoint(x: 9, y: 0))
                    p.addLine(to: CGPoint(x: 9, y: 6))
                    p.addQuadCurve(to: CGPoint(x: 6, y: 9), control: CGPoint(x: 9, y: 9))
                    p.addLine(to: CGPoint(x: 0, y: 9))
                }
                .stroke(Hive.muted.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 9, height: 9)
                .padding(4)
            }
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let start = resizeStart ?? frame
                        resizeStart = start
                        // not beyond the window edge
                        let w = min(max(start.width + v.translation.width, Self.minSize.width),
                                    max(Self.minSize.width, bounds.width - start.minX)).rounded()
                        let h = min(max(start.height + v.translation.height, Self.minSize.height),
                                    max(Self.minSize.height, bounds.height - start.minY)).rounded()
                        notes.setFrame(note.id, CGRect(x: start.minX, y: start.minY, width: w, height: h))
                    }
                    .onEnded { _ in
                        notes.persistFrames()
                        resizeStart = nil
                    }
            )
            .help("Resize")
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// An empty note goes right away; one with text asks once ("Delete?" for a few seconds).
    private func askDelete() {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.remove(note.id); return }
        confirmDelete = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            confirmDelete = false
        }
    }
}

/// Title bar button "Note from Answer": lists the selected session's recent answers; a click on one makes
/// it a note. (Taking simply the last message would often catch a status line instead of the answer.)
struct AnswerNoteButton: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var notes: NotesStore
    @AppStorage("notesVisible") private var notesVisible = false
    @State private var card = FloatingCard()
    @State private var anchor: NSView?

    var body: some View {
        Button { toggle() } label: { Label("Note from Answer", systemImage: "text.bubble") }
            .background { AnchorReader { anchor = $0 } }
            .help(store.selected == nil ? "Select a session to turn one of its answers into a note"
                  : "Pick one of \(store.selected ?? "")'s recent answers as a note")
            .disabled(store.selected == nil)
            .onDisappear { card.close() }
    }

    private func toggle() {
        if card.isOpen { card.close(); return }
        guard let name = store.selected, let anchor else { return }
        Task {
            let replies = await notes.recentReplies(of: name)
            card.show(below: anchor) {
                AnswerPicker(session: name, replies: replies) { text in
                    card.close()
                    notesVisible = true
                    notes.show(name)
                    notes.add(to: name, text: text)
                }
            }
        }
    }
}

/// The list inside the card: time and the beginning of each answer, newest first.
private struct AnswerPicker: View {
    let session: String
    let replies: [Said]
    let pick: (String) -> Void
    @State private var hovered: Int?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func time(_ at: String?) -> String {
        guard let at, let d = Self.iso.date(from: at) else { return "" }
        return d.formatted(date: Calendar.current.isDateInToday(d) ? .omitted : .abbreviated, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Answers of \(session)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Hive.ink)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            Text(replies.isEmpty ? "No answer found yet." : "Click one to keep it as a note.")
                .font(.system(size: 12)).foregroundStyle(Hive.muted)
                .padding(.horizontal, 16).padding(.bottom, 10)
            if !replies.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(replies.enumerated()), id: \.offset) { i, r in
                            Button { pick(r.text) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(time(r.at)).font(.system(size: 11)).foregroundStyle(Hive.muted).monospacedDigit()
                                    Text(r.text.prefix(400)).font(.system(size: 12.5)).foregroundStyle(Hive.ink2)
                                        .lineLimit(3).multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(hovered == i ? Hive.bg : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { inside in
                                if inside { hovered = i } else if hovered == i { hovered = nil }
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .padding(.bottom, 8)
        .frame(width: 440)
    }
}
