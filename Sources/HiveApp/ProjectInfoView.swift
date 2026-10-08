import AppKit
import MarkdownUI
import SwiftUI
import HiveCore

/// Project info of a session's project (spec 2026-10-08 §2): Markdown like the handover, Edit switches to
/// the raw text. Leaving edit mode any way except Cancel saves into the file that was open when editing started.
struct ProjectInfoView: View {
    @EnvironmentObject private var projects: ProjectInfoStore
    let cwd: String?
    let sessionPrefix: String?
    let startEditing: Bool
    /// snapshot of the file being edited (nil = reading)
    @State private var editing: ProjectInfo?
    @State private var draft = ""
    @State private var error: String?

    private var resolved: (slug: String, info: ProjectInfo?)? { projects.resolve(cwd: cwd) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Hive.hair).frame(height: 1)
            if editing != nil {
                TextEditor(text: $draft)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 26).padding(.vertical, 14)
            } else if let info = resolved?.info {
                ScrollView {
                    Markdown(ProjectInfo.linkified(info.body)).markdownTheme(.hive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 32).padding(.vertical, 26)
                        .textSelection(.enabled)
                        .environment(\.openURL, OpenURLAction { url in
                            NSWorkspace.shared.open(url)
                            return .handled
                        })
                }
                .scrollIndicators(.never)
            } else {
                ContentUnavailableView {
                    Label("No project info yet", systemImage: "info.circle")
                } description: {
                    Text("Links, test accounts and notes for this project. Stored in ~/.claude/project-info, outside every repo.")
                } actions: {
                    Button("Create", action: create).disabled(createDefaults == nil)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear { if startEditing { beginEditing() } }
        .onDisappear { saveIfEditing() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveIfEditing()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let r = resolved {
                Text(r.slug).font(.system(size: 14, weight: .semibold))
                if r.info != nil {
                    Button((projects.path(r.slug) as NSString).abbreviatingWithTildeInPath) { projects.openInEditor(r.slug) }
                        .buttonStyle(.link).font(.system(size: 12))
                        .help("Open the file in the default editor")
                }
            }
            Spacer()
            if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(1) }
            if editing != nil {
                Button("Cancel") { editing = nil; error = nil }.controlSize(.regular)
                Button("Done") { saveIfEditing() }.controlSize(.regular).buttonStyle(.borderedProminent)
            } else if resolved?.info != nil {
                Button("Edit", action: beginEditing).controlSize(.regular)
            }
        }
        .padding(.horizontal, 20).frame(height: 48)
    }

    private var createDefaults: (slug: String, folder: String)? {
        cwd.flatMap { ProjectInfo.createDefaults(cwd: $0) }
    }

    private func beginEditing() {
        guard let info = resolved?.info else { return }
        editing = info
        draft = info.body
    }

    private func create() {
        guard let d = createDefaults else { return }
        let prefix = sessionPrefix.flatMap { ProjectInfo.isValidSlug($0) ? $0 : nil }
        let info = ProjectInfo.template(slug: d.slug, folder: d.folder, prefix: prefix)
        do {
            try projects.save(info)
            editing = info
            draft = info.body
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveIfEditing() {
        guard var info = editing else { return }
        info.body = draft
        do {
            try projects.save(info)
            editing = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
