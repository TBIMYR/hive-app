import SwiftTerm
import SwiftUI
import HiveCore

struct TerminalPane: View {
    @EnvironmentObject private var store: StateStore
    let session: Session?
    @State private var message: String?
    /// Selected segment, nil = the session's default (spec 2026-10-08 §2)
    @State private var pane: Pane?
    /// Open the project view in edit mode (after New Project)
    @State private var editOnOpen = false
    @EnvironmentObject private var projects: ProjectInfoStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if let s = session {
                HStack(spacing: 8) {
                    Circle().fill(store.color(for: s.groupKey)).frame(width: 8, height: 8)
                    Text(s.name).font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 4)
                    if let msg = message { Text(msg).font(.caption).foregroundStyle(Hive.muted) }
                    StatusLabel(status: store.status(s), since: s.alive == true ? dur(s.statusUpdatedAt, now: store.now) : "")
                    Picker("", selection: Binding(get: { current(s) }, set: { pane = $0; editOnOpen = false })) {
                        ForEach(panes(s), id: \.self) { p in
                            Text(p == .main ? mainLabel(s) : p == .handover ? "Handover" : "Project").tag(p)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.regular).fixedSize()
                    .help("Terminal, handover, or this project's info (links, test accounts, notes)")
                }
                .padding(.horizontal, 14).frame(height: 50)
                Rectangle().fill(Hive.hair).frame(height: 1)
                content(for: s)
            } else {
                ContentUnavailableView("No session selected", systemImage: "terminal",
                                       description: Text("Click a session on the left."))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // a large card like the session cards: white, rounded, soft shadow (hairline on dark)
        .background(Hive.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { if scheme == .dark { RoundedRectangle(cornerRadius: 16).strokeBorder(Hive.hair, lineWidth: 1) } }
        .shadow(color: scheme == .dark ? .clear : .black.opacity(0.05), radius: 1, y: 1)
        .shadow(color: scheme == .dark ? .clear : .black.opacity(0.05), radius: 12, y: 6)
        .onChange(of: session?.name) { _, name in
            message = nil
            pane = nil
            editOnOpen = false
            // New Project asked to open this session's project info in edit mode
            if let name, projects.pendingEdit == name {
                projects.pendingEdit = nil
                pane = .project
                editOnOpen = true
            }
        }
        // jump key: back to the default view so the terminal can get focus
        .onChange(of: store.focusRequest) { pane = nil; editOnOpen = false }
    }

    enum Pane: Hashable { case main, handover, project }

    /// Segments per session: offline with a handover has no main view of its own.
    private func panes(_ s: Session) -> [Pane] {
        let hasHandover = s.hasHandover == true
        if store.tmux(s) == nil && s.alive != true && hasHandover { return [.handover, .project] }
        return hasHandover ? [.main, .handover, .project] : [.main, .project]
    }

    private func current(_ s: Session) -> Pane {
        let all = panes(s)
        if let pane, all.contains(pane) { return pane }
        return all[0]
    }

    private func mainLabel(_ s: Session) -> String {
        store.tmux(s) != nil ? "Terminal" : s.alive == true ? "Session" : "Offline"
    }

    @ViewBuilder
    private func content(for s: Session) -> some View {
        switch current(s) {
        case .project:
            ProjectInfoView(cwd: store.cwd(s), sessionPrefix: SessionNaming.prefix(s.name), startEditing: editOnOpen)
                .id("\(s.name)#\(store.cwd(s) ?? "")")
        case .handover:
            HandoverView(name: s.name)
        case .main:
            mainContent(for: s)
        }
    }

    @ViewBuilder
    private func mainContent(for s: Session) -> some View {
        if Tmux.path == nil {
            ContentUnavailableView("tmux missing", systemImage: "exclamationmark.triangle",
                                   description: Text("brew install tmux"))
                .frame(maxHeight: .infinity)
        } else if let t = store.tmux(s) {
            TmuxTerminal(name: t, focusRequest: store.focusRequest).id("\(t)#\(store.terminalEpoch)")
                .padding(.horizontal, 28).padding(.top, 6)
        } else if s.alive == true {
            VStack(spacing: 12) {
                ContentUnavailableView("Runs in iTerm", systemImage: "macwindow",
                                       description: Text("This session has no tmux session. Start new sessions with the plus in the toolbar or ⌘N."))
                if s.kind != "bg" {
                    Button("Show in iTerm") {
                        Task { message = await store.focusInITerm(s) ?? "→ iTerm" }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else if s.hasHandover == true {
            // offline: only the handover is still there, so show it right away
            HandoverView(name: s.name)
        } else {
            ContentUnavailableView("Offline", systemImage: "moon.zzz",
                                   description: Text("No terminal and no handover."))
                .frame(maxHeight: .infinity)
        }
    }
}

/// Which terminal is currently being typed into (tmux name, up to 3 s after the last keypress).
/// This session's answer buttons stay disabled for that long, so nothing collides with manual input.
@MainActor
final class TerminalActivity: ObservableObject {
    static let shared = TerminalActivity()
    @Published private(set) var typingIn: String?
    private var clear: DispatchWorkItem?

    func typed(in name: String) {
        if typingIn != name { typingIn = name }
        clear?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.typingIn = nil }
        clear = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    /// Responses from the terminal itself (focus in/out, device queries) don't count as typing.
    nonisolated static func isTyping(_ data: ArraySlice<UInt8>) -> Bool {
        let s = String(decoding: data, as: UTF8.self)
        if s == "\u{1B}[I" || s == "\u{1B}[O" { return false }
        if ["\u{1B}[?", "\u{1B}[>", "\u{1B}]", "\u{1B}P"].contains(where: s.hasPrefix) { return false }
        // cursor position "ESC [ 12;1 R"
        return !(s.hasPrefix("\u{1B}[") && s.hasSuffix("R") && s.count > 4)
    }
}

/// SwiftTerm terminal that remembers a focus request until it's attached to a window. After a
/// session switch, the view is recreated because of `.id` and has no window yet at the first updateNSView.
final class HiveTerminalView: LocalProcessTerminalView {
    var wantsFocus = false
    /// tmux session this terminal is attached to
    var sessionName = ""

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        if TerminalActivity.isTyping(data) {
            let name = sessionName
            Task { @MainActor in TerminalActivity.shared.typed(in: name) }
        }
    }

    func takeFocusIfWanted() {
        guard wantsFocus, let window else { return }
        wantsFocus = false
        window.makeFirstResponder(self)
    }

    private var keyMonitor: Any?

    /// Option is not Meta here (`optionAsMetaKey = false`), so Option+L types "@" and the other characters
    /// of the keyboard layout. The few Meta combinations that matter are sent by hand: Shift/Option+Return
    /// = ESC CR (new line in Claude Code; plain CR would send the message), Option+←/→ = word jump,
    /// Option+Delete = delete word. SwiftTerm's keyDown can't be overridden, so a local monitor catches
    /// them while this terminal has the focus.
    private func watchMetaKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window, self.window?.firstResponder === self,
                  let seq = Self.metaSequence(keyCode: e.keyCode,
                                              modifiers: e.modifierFlags.intersection([.shift, .control, .option, .command]))
            else { return e }
            self.send(txt: seq)
            return nil
        }
    }

    static func metaSequence(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        switch (keyCode, modifiers) {
        case (36, .shift), (76, .shift), (36, .option), (76, .option): "\u{1B}\r"
        case (123, .option): "\u{1B}b"
        case (124, .option): "\u{1B}f"
        case (51, .option): "\u{1B}\u{7F}"
        default: nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watchMetaKeys()
        // drag files and images in like in iTerm: the path gets typed (Claude then attaches images)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        takeFocusIfWanted()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        var paths = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .map(\.path)
        // image without a file (e.g. from the browser): save it as PNG into a temp folder
        if paths.isEmpty, let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("hive-drop-\(UUID().uuidString.prefix(8)).png")
            if (try? png.write(to: url)) != nil { paths = [url.path] }
        }
        guard !paths.isEmpty else { return false }
        send(txt: paths.map(Self.shellEscaped).joined(separator: " ") + " ")
        window?.makeFirstResponder(self)
        return true
    }

    /// Path like iTerm, with backslashes before spaces and special characters
    static func shellEscaped(_ path: String) -> String {
        let special = Set(" \\'\"()[]{}&;|<>*?$`!#~")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }
}

/// SwiftTerm terminal that attaches to the session via `tmux attach`.
struct TmuxTerminal: NSViewRepresentable {
    let name: String
    /// Counter from the store; when it changes, the terminal grabs focus
    let focusRequest: Int
    @Environment(\.colorScheme) private var scheme

    final class Coordinator {
        /// last focus request that was handled
        var focusSeen = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // same tones as the cards in the hive dashboard (--card / --ink).
    // SwiftTerm applies colors statically when set, so set them again on every mode change.
    private func applyColors(_ view: HiveTerminalView) {
        let dark = scheme == .dark
        view.nativeBackgroundColor = NSColor(hex: dark ? 0x141414 : 0xFFFFFF)
        view.nativeForegroundColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.caretColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
    }

    func makeNSView(context: Context) -> HiveTerminalView {
        let view = HiveTerminalView(frame: .zero)
        view.sessionName = name
        // proportional fonts don't work in the terminal grid (every cell as wide as the widest
        // character, "C l a u d e"); to check: HIVE_TERM_FONT=system
        // otherwise like a typical iTerm profile: MesloLGS NF 13 (bold/italic from the family's own cuts),
        // thin strokes on Retina (= without font smoothing), cursor as a bar without blinking.
        view.font = ProcessInfo.processInfo.environment["HIVE_TERM_FONT"] == "system"
            ? NSFont.systemFont(ofSize: 13)
            : NSFont(name: "MesloLGS-NF-Regular", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.fontSmoothing = false
        // Option types the layout's characters (Option+L = @ on German keyboards); Meta keys: watchMetaKeys
        view.optionAsMetaKey = false
        view.getTerminal().setCursorStyle(.steadyBar)
        applyColors(view)
        hideScroller(view)
        view.startProcess(executable: Tmux.path!,
                          args: Tmux.attachArgs(name),
                          environment: Tmux.environmentList(),
                          execName: "tmux")
        // a new terminal always gets focus (as before), as soon as it's attached to the window
        context.coordinator.focusSeen = focusRequest
        view.wantsFocus = true
        return view
    }

    func updateNSView(_ nsView: HiveTerminalView, context: Context) {
        applyColors(nsView)
        hideScroller(nsView)
        if context.coordinator.focusSeen != focusRequest {
            context.coordinator.focusSeen = focusRequest
            nsView.wantsFocus = true
        }
        nsView.takeFocusIfWanted()
    }

    // tmux keeps the history, SwiftTerm's own scroller stays empty; it's private, so access it via the subviews
    private func hideScroller(_ view: HiveTerminalView) {
        view.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    static func dismantleNSView(_ nsView: HiveTerminalView, coordinator: Coordinator) {
        // only ends the attach process; the tmux session keeps running
        nsView.terminate()
    }
}
