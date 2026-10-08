import AppKit
import SwiftUI
import HiveCore

/// "New Project" (spec 2026-10-08 §3): create, clone or register the folder, write the project file,
/// start `<prefix>.pm` and open its project info in edit mode.
struct NewProjectSheet: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var projects: ProjectInfoStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable { case empty = "Empty", clone = "Clone from GitHub", existing = "Existing folder" }

    @State private var name = ""
    @State private var prefix = ""
    /// last prefix the dialog suggested itself; anything else was typed and is kept
    @State private var lastSuggested = ""
    @State private var location = Project.defaultDevRoot
    @State private var existingFolder = ""
    @State private var kind = Kind.empty
    @State private var repo = ""
    @State private var startPM = Tmux.path != nil
    @State private var error: String?
    @State private var job: LongRun?

    private var folder: String { kind == .existing ? existingFolder : "\(location)/\(name)" }
    private var source: ProjectCreate.Source {
        switch kind {
        case .empty: .empty
        case .clone: .clone(repo)
        case .existing: .existing
        }
    }
    private var pmName: String { "\(prefix).pm" }
    private var pmRunning: Bool { store.runningNames.contains(pmName) || Tmux.hasSession(pmName) }

    /// Sessions working in this folder (or below it).
    private func sessions(in f: String) -> [Session] {
        store.displaySessions.filter { s in
            let c = store.cwd(s) ?? ""
            return !f.isEmpty && (c == f || c.hasPrefix(f + "/"))
        }
    }

    /// Prefixes of other projects and of running sessions outside the chosen folder.
    private var takenPrefixes: Set<String> {
        let inside = Set(sessions(in: folder).map(\.name))
        let running = store.runningNames.subtracting(inside).compactMap(SessionNaming.prefix)
        return Set(projects.projects.compactMap(\.prefix)).union(running)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project").font(.headline)
            Form {
                Picker("Source", selection: $kind) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if kind == .existing {
                    LabeledContent("Folder") {
                        folderButton(existingFolder.isEmpty ? "Choose…" : tilde(existingFolder), start: location, onPick: pickExisting)
                    }
                }
                TextField("Name", text: $name, prompt: Text("e.g. lumen"))
                TextField("Prefix", text: $prefix, prompt: Text("e.g. lu"))
                if kind != .existing {
                    LabeledContent("Location") {
                        folderButton(tilde(location), start: location) { location = $0 }
                    }
                    if !name.isEmpty {
                        LabeledContent("Folder") { Text(tilde(folder)).foregroundStyle(.secondary) }
                    }
                }
                if kind == .clone {
                    TextField("Repository", text: $repo, prompt: Text("owner/repo or URL"))
                }
                Toggle("Start PM session \(prefix.isEmpty ? "<prefix>.pm" : pmName)", isOn: $startPM)
                    .disabled(Tmux.path == nil || pmRunning)
            }
            Text("Also creates ~/.claude/project-info/\(name.isEmpty ? "<name>" : name).md for links, test accounts and notes.")
                .font(.caption).foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if job != nil {
                    ProgressView().controlSize(.small)
                    Text(kind == .clone ? "Cloning…" : "Creating…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create", action: create).keyboardShortcut(.defaultAction)
                    .disabled(job != nil || name.isEmpty || prefix.isEmpty || (kind == .existing && existingFolder.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 500)
        .onChange(of: name) { _, n in suggestPrefix(from: n) }
        .onChange(of: pmRunning) { _, running in if running { startPM = false } }
        .onAppear { if pmRunning { startPM = false } }
    }

    private func tilde(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }

    /// Fills the prefix as long as it wasn't typed by hand.
    private func suggestPrefix(from n: String, preferred: String? = nil) {
        guard prefix.isEmpty || prefix == lastSuggested else { return }
        let next = preferred ?? ProjectInfo.suggestPrefix(name: n, taken: takenPrefixes)
        lastSuggested = next
        prefix = next
    }

    /// Existing folder: name from the folder, prefix from the sessions already working there.
    private func pickExisting(_ path: String) {
        existingFolder = path
        let counts = Dictionary(grouping: sessions(in: path).compactMap { SessionNaming.prefix($0.name) }, by: { $0 })
        let common = counts.max { $0.value.count < $1.value.count }?.key
        if name.isEmpty || ProjectInfo.slug(from: name) == nil {
            name = ProjectInfo.slug(from: (path as NSString).lastPathComponent) ?? ""
        }
        suggestPrefix(from: name, preferred: common.flatMap { ProjectInfo.isValidSlug($0) ? $0 : nil })
    }

    private func folderButton(_ title: String, start: String, onPick: @escaping (String) -> Void) -> some View {
        Button(title) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = URL(fileURLWithPath: start)
            if panel.runModal() == .OK, let url = panel.url { onPick(url.path) }
        }
    }

    private func create() {
        let input = ProjectCreate.Input(slug: name, prefix: prefix, folder: folder, source: source)
        if let e = ProjectCreate.validate(input, registered: projects.projects, takenPrefixes: takenPrefixes,
                                          exists: { FileManager.default.fileExists(atPath: $0) }) {
            error = e
            return
        }
        error = nil
        let hasGh = LoginShell.findExecutable("gh", path: LoginShell.path) != nil
        guard let argv = ProjectCreate.command(source, folder: folder, hasGh: hasGh) else {
            finish(input)
            return
        }
        var env = ProcessInfo.processInfo.environment.filter { !Tmux.isInherited($0.key) }
        if let p = LoginShell.path { env["PATH"] = p }
        env.merge(ProjectCreate.quietEnv) { $1 }
        let run = LongRun("/usr/bin/env", argv, env: env)
        job = run
        Task {
            let r = await Task.detached { run.run(timeout: 300) }.value
            job = nil
            if r.status == 0 && !r.cancelled {
                finish(input)
                return
            }
            // validation made sure the folder didn't exist before, so only what this dialog created is removed
            try? FileManager.default.removeItem(atPath: input.folder)
            if r.cancelled {
                dismiss()
                return
            }
            let tail = r.err.split(separator: "\n").suffix(3).joined(separator: "\n")
            error = r.timedOut ? "Timed out after 5 minutes." : (tail.isEmpty ? "Failed (exit \(r.status))." : tail)
        }
    }

    private func finish(_ input: ProjectCreate.Input) {
        let info = ProjectInfo.template(slug: input.slug, folder: input.folder, prefix: input.prefix)
        do {
            try projects.save(info)
        } catch {
            self.error = error.localizedDescription
            return
        }
        if startPM && Tmux.path != nil && !pmRunning {
            if let e = Tmux.newSession(name: pmName, dir: input.folder) {
                store.notice = "Project \(input.slug) created, but \(pmName) did not start: \(e)"
            } else {
                projects.pendingEdit = pmName
                store.selected = pmName
                store.refreshSoon()
            }
        }
        dismiss()
    }

    private func cancel() {
        if let job { job.cancel() } else { dismiss() }
    }
}
