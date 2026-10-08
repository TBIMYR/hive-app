import AppKit
import Foundation
import HiveCore

/// Project files from `~/.claude/project-info` (to try it out: `HIVE_PROJECT_INFO=<dir>`).
/// Creates the folder before the watcher starts (FSEvents doesn't report a folder created later).
@MainActor
final class ProjectInfoStore: ObservableObject {
    @Published private(set) var projects: [ProjectInfo] = []
    /// "Open the project view in edit mode" for this session, consumed once by TerminalPane (New Project)
    @Published var pendingEdit: String?
    let dir: String
    private var watcher: Watcher?

    init(dir: String = ProcessInfo.processInfo.environment["HIVE_PROJECT_INFO"] ?? ProjectInfo.defaultDir) {
        self.dir = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        load()
        watcher = Watcher(paths: [dir]) { [weak self] in
            Task { @MainActor in self?.load() }
        }
    }

    func load() {
        let now = ProjectInfo.loadAll(dir: dir)
        if now != projects { projects = now }
    }

    func resolve(cwd: String?) -> (slug: String, info: ProjectInfo?)? {
        cwd.flatMap { ProjectInfo.resolve(cwd: $0, in: projects) }
    }

    func save(_ info: ProjectInfo) throws {
        try info.write(dir: dir)
        load()
    }

    func path(_ slug: String) -> String { ProjectInfo.path(dir: dir, slug: slug) }

    func openInEditor(_ slug: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path(slug))) }
}
