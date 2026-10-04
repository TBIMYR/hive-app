import AppKit
import SwiftUI

/// Prefill for the dialog, e.g. from a project group's "+".
struct NewSessionPreset: Identifiable {
    var name = ""
    var dir: String?
    var id: String { name + (dir ?? "") }
}

enum SessionNaming {
    /// "lu.04" → "lu"; names without a dot have no prefix.
    static func prefix(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let p = String(name[..<dot])
        return p.isEmpty ? nil : p
    }

    /// Most common prefix of a group, next free worker name ("lu.05").
    static func nextName(in sessions: [Session]) -> String? {
        let prefixes = sessions.compactMap { prefix($0.name) }
        guard let p = Dictionary(grouping: prefixes, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key
        else { return nil }
        let used = sessions.compactMap { s -> Int? in
            guard prefix(s.name) == p else { return nil }
            return Int(s.name.split(separator: ".").last ?? "")
        }
        return String(format: "%@.%02d", p, (used.max() ?? 0) + 1)
    }

    /// Folder of another session with the same prefix (PM preferred).
    static func dir(for name: String, in sessions: [Session]) -> String? {
        guard let p = prefix(name) else { return nil }
        let same = sessions.filter { prefix($0.name) == p && ($0.cwd ?? "").isEmpty == false }
        return (same.first { $0.isPm == true } ?? same.first)?.cwd
    }

    /// Known project folders from the running sessions, sorted by project name.
    static func projects(in sessions: [Session]) -> [(label: String, dir: String)] {
        var seen = Set<String>()
        return sessions.compactMap { s -> (String, String)? in
            guard let d = s.cwd, !d.isEmpty, seen.insert(d).inserted else { return nil }
            return ((s.project?.isEmpty == false ? s.project! : (d as NSString).lastPathComponent), d)
        }
        .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}

struct NewSessionSheet: View {
    @EnvironmentObject private var store: StateStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var dir: String
    @State private var dirChosen: Bool
    @State private var error: String?
    let onCreated: (String) -> Void

    init(preset: NewSessionPreset, onCreated: @escaping (String) -> Void) {
        _name = State(initialValue: preset.name)
        _dir = State(initialValue: preset.dir ?? "")
        _dirChosen = State(initialValue: preset.dir != nil)
        self.onCreated = onCreated
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New session").font(.headline)
            Form {
                TextField("Name", text: $name, prompt: Text("e.g. lu.04"))
                    .onChange(of: name) { _, n in
                        // derive the folder from the prefix as long as none was chosen explicitly
                        if !dirChosen, let d = SessionNaming.dir(for: n, in: store.sessions) { dir = d }
                    }
                LabeledContent("Folder") {
                    HStack {
                        Menu(dir.isEmpty ? "Choose project" : (dir as NSString).abbreviatingWithTildeInPath) {
                            ForEach(SessionNaming.projects(in: store.sessions), id: \.dir) { p in
                                Button("\(p.label)  –  \((p.dir as NSString).abbreviatingWithTildeInPath)") {
                                    dir = p.dir
                                    dirChosen = true
                                }
                            }
                            Divider()
                            Button("Other folder …", action: chooseFolder)
                        }
                        .fixedSize()
                    }
                }
            }
            Text("Opens a terminal in this folder. `claude -n \(trimmedName.isEmpty ? "<name>" : trimmedName)` is already typed at the prompt: press Enter, or edit it first, e.g. to `codex`.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open terminal", action: start).keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || dir.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: dir.isEmpty ? NSHomeDirectory() + "/Development" : dir)
        if panel.runModal() == .OK, let url = panel.url {
            dir = url.path
            dirChosen = true
        }
    }

    private func start() {
        let n = trimmedName
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            error = "Folder does not exist: \(dir)"
            return
        }
        if store.sessions.contains(where: { $0.name == n && $0.alive == true }) {
            error = "A session \(n) is already running"
            return
        }
        if Tmux.hasSession(n) { error = "tmux session \(n) is already running"; return }
        if let e = Tmux.newSession(name: n, dir: dir) { error = e; return }
        onCreated(n)
        dismiss()
    }
}
