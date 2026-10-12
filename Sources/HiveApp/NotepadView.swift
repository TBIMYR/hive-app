import SwiftUI
import HiveCore

/// The notepads per session from `~/.claude/hive/notes/` (to try it out: `HIVE_NOTES=<path>`). Picks up
/// what is written from outside (`cc-note`) through the watcher.
@MainActor
final class NotesStore: ObservableObject {
    /// Sessions that have notes, for the badges
    @Published private(set) var sessions: Set<String> = []
    /// Counts up whenever something changed in the folder
    @Published private(set) var revision = 0
    /// Session whose notepad should take the keyboard focus
    @Published var focusRequest: String?
    let root = Notes.root()
    private var watcher: Watcher?

    init() {
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        Notes.migrate(root: root)
        load()
        watcher = Watcher(paths: [root]) { [weak self] in
            Task { @MainActor in self?.load() }
        }
    }

    private func load() {
        let s = Notes.sessions(root: root)
        if s != sessions { sessions = s }
        revision += 1
    }

    func text(_ session: String) -> String { Notes.read(root: root, session: session) }

    func save(_ session: String, _ text: String) {
        Notes.write(root: root, session: session, text: text)
        let has = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if has != sessions.contains(session) {
            if has { sessions.insert(session) } else { sessions.remove(session) }
        }
    }
}

/// Small note icon for sessions that have notes; nothing otherwise.
struct NoteBadge: View {
    let name: String
    @EnvironmentObject private var notes: NotesStore

    var body: some View {
        if notes.sessions.contains(name) {
            Image(systemName: "note.text").font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Hive.muted)
                .fixedSize()
                .help("Has notes (⌘T)")
        }
    }
}

/// The session's notepad: one Markdown text, always editable (see NoteEditor), saved while typing.
struct NotepadView: View {
    @EnvironmentObject private var notes: NotesStore
    let name: String
    @State private var text = ""
    /// what is on disk as far as this view knows (trimmed)
    @State private var synced = ""
    @State private var focused = false

    var body: some View {
        NoteEditor(text: $text, wantsFocus: notes.focusRequest == name) { now in
            focused = now
            if now, notes.focusRequest == name { notes.focusRequest = nil }
        }
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text("Notes for \(name). Markdown works; they stay until you delete them.")
                    .font(.system(size: 15)).foregroundStyle(Hive.muted)
                    .padding(.horizontal, 16).padding(.top, 2)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 8)
        .onAppear {
            synced = notes.text(name)
            text = synced
        }
        .onChange(of: notes.revision) { takeOver() }
        .onChange(of: text) { _, new in
            let t = new.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t != synced else { return }
            synced = t
            notes.save(name, new)
        }
    }

    /// Changed from outside (`cc-note`): something appended goes below what is being typed; anything else
    /// replaces the text unless the cursor is in it.
    private func takeOver() {
        let disk = notes.text(name)
        guard disk != synced else { return }
        if !synced.isEmpty, disk.hasPrefix(synced) {
            let added = String(disk.dropFirst(synced.count))
            synced = disk
            text = text.trimmingCharacters(in: .whitespacesAndNewlines) + added
        } else if !focused {
            synced = disk
            text = disk
        }
    }
}
