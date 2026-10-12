import SwiftTerm
import SwiftUI
import HiveCore

/// The window's content: the overview and the selected session's views as tiles that can be arranged by
/// dragging (see DockLayout). Every tile with session views is a card; the one with the terminal carries
/// the session's name and status.
struct Workspace: View {
    @EnvironmentObject private var store: StateStore
    @State private var message: String?
    /// Open the project view in edit mode (after New Project)
    @State private var editOnOpen = false
    /// Tab (or the overview's view switcher) that is being dragged to another place
    @State private var drag: DockDrag?
    /// Where the groups are in the window, to find the drop target
    @State private var frames: [DockPanel: CGRect] = [:]
    @State private var area: CGSize = .zero
    @EnvironmentObject private var projects: ProjectInfoStore
    @EnvironmentObject private var dock: DockStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = store.displaySessions.first { $0.name == store.selected }
        let visible = dock.layout.visible(available(s))
        let header = visible.flatMap(headerGroup)
        ZStack {
            if let visible { node(visible, s, header: header, edges: .all) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Hive.bg)
        .coordinateSpace(name: Dock.space)
        .background { GeometryReader { g in Color.clear.onChange(of: g.size, initial: true) { area = g.size } } }
        .onPreferenceChange(DockFrames.self) { frames = $0 }
        .overlay { if let drag { DockDropOverlay(drag: drag, target: target(drag)?.rect) } }
        .onChange(of: store.selected) { _, name in
            message = nil
            editOnOpen = false
            // back to the session itself, as far as it shares its tile with other tabs
            dock.change { $0.select(.main) }
            // New Project asked to open this session's project info in edit mode
            if let name, projects.pendingEdit == name {
                projects.pendingEdit = nil
                dock.change { $0.select(.project) }
                editOnOpen = true
            }
        }
        // jump key: back to the terminal so it can get focus
        .onChange(of: store.focusRequest) { dock.change { $0.select(.main) }; editOnOpen = false }
    }

    /// Panels to show: offline with a handover has no main view of its own; without a selection the main
    /// tile says so.
    private func available(_ s: Session?) -> Set<DockPanel> {
        guard let s else { return [.overview, .main] }
        var all: Set<DockPanel> = [.overview, .main, .project, .notes]
        if s.hasHandover == true {
            all.insert(.handover)
            if store.tmux(s) == nil && s.alive != true { all.remove(.main) }
        }
        return all
    }

    /// First panel of the group that carries the session's name and status: the one with the terminal,
    /// otherwise the first with session views.
    private func headerGroup(_ v: DockLayout.Visible) -> DockPanel? {
        func groups(_ v: DockLayout.Visible) -> [[DockPanel]] {
            switch v {
            case .group(let panels, _): [panels]
            case .split(_, _, let children): children.flatMap { groups($0.node) }
            }
        }
        let all = groups(v).filter { $0 != [.overview] }
        return (all.first { $0.contains(.main) } ?? all.first)?.first
    }

    private func item(_ p: DockPanel, _ s: Session) -> DockTabs.Item {
        switch p {
        case .overview: Self.overviewItem
        case .main:
            store.tmux(s) != nil ? .init(panel: p, title: "Terminal", symbol: "terminal", help: "Terminal")
                : s.alive == true ? .init(panel: p, title: "Session", symbol: "macwindow", help: "Session")
                : .init(panel: p, title: "Offline", symbol: "moon.zzz", help: "Offline")
        case .handover: .init(panel: p, title: "Handover", symbol: "doc.text", help: "This session's handover")
        case .project: .init(panel: p, title: "Project", symbol: "info.circle", help: "This project's links, test accounts and notes")
        case .notes: .init(panel: p, title: "Notes", symbol: "note.text", help: "Your notes on this session (⌘T)")
        }
    }

    private static let overviewItem = DockTabs.Item(panel: .overview, title: "Sessions", symbol: "square.grid.2x2", help: "All sessions")

    private func tabs(_ panels: [DockPanel], _ selected: DockPanel, _ s: Session, titles: Bool = true) -> some View {
        DockTabs(items: panels.map { item($0, s) }, selected: selected, titles: titles, drag: $drag,
                 select: { p in
                     editOnOpen = false
                     dock.change { $0.select(p) }
                 },
                 drop: { drop($0) },
                 move: { p, zone in
                     if let zone { dock.change { $0.move(p, to: p, zone: zone) } } else { dock.reset() }
                 })
    }

    private func drop(_ d: DockDrag) {
        guard let t = target(d) else { return }
        dock.change(t.apply)
    }

    private struct DropTarget {
        let rect: CGRect
        let apply: (inout DockLayout) -> Void
    }

    /// Where a dragged tab would land: at an edge of the window across everything, or on the group under
    /// the pointer (on its tabs or beside it). nil where a drop changes nothing.
    private func target(_ d: DockDrag) -> DropTarget? {
        let window = CGRect(origin: .zero, size: area)
        if let edge = DockLayout.windowEdge(at: d.location, in: window, margin: Dock.windowEdge) {
            var probe = dock.layout
            probe.move(d.panel, toEdge: edge)
            if probe != dock.layout {
                return DropTarget(rect: Self.part(of: window, edge, share: DockLayout.edgeShare)) { $0.move(d.panel, toEdge: edge) }
            }
        }
        guard let (anchor, frame) = frames.first(where: { $0.value.contains(d.location) }) else { return nil }
        let zone = DockLayout.zone(at: d.location, in: frame, center: d.panel != .overview && anchor != .overview)
        var probe = dock.layout
        probe.move(d.panel, to: anchor, zone: zone)
        guard probe != dock.layout else { return nil }
        return DropTarget(rect: Self.part(of: frame, zone, share: 0.5)) { $0.move(d.panel, to: anchor, zone: zone) }
    }

    private static func part(of r: CGRect, _ zone: DockLayout.Zone, share: Double) -> CGRect {
        var r = r
        switch zone {
        case .center: break
        case .left: r.size.width *= share
        case .right: r.origin.x += r.width * (1 - share); r.size.width *= share
        case .top: r.size.height *= share
        case .bottom: r.origin.y += r.height * (1 - share); r.size.height *= share
        }
        return r
    }

    /// Reports the tile's frame for drops.
    private func framed(_ anchor: DockPanel) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: DockFrames.self, value: [anchor: g.frame(in: .named(Dock.space))])
        }
    }

    /// A tile or a split of tiles. `edges` are the sides at which the node touches the window; there a card
    /// keeps the full margin, between tiles half of it each.
    private func node(_ v: DockLayout.Visible, _ s: Session?, header: DockPanel?, edges: Edge.Set) -> AnyView {
        switch v {
        case .group(let panels, _) where panels == [.overview]:
            return AnyView(
                OverviewView(edges: edges, dragged: { overviewDragged($0, ended: $1) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { framed(.overview) }
            )
        case .group(let panels, let selected):
            func inset(_ e: Edge.Set) -> CGFloat { edges.contains(e) ? Hive.margin : Hive.margin / 2 }
            return AnyView(
                VStack(spacing: 0) {
                    if let s {
                        if panels[0] == header {
                            HStack(spacing: 8) {
                                Circle().fill(store.color(for: s.groupKey)).frame(width: 8, height: 8)
                                Text(s.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                if let msg = message { Text(msg).font(.caption).foregroundStyle(Hive.muted).lineLimit(1) }
                                StatusLabel(status: store.status(s), since: s.alive == true ? dur(s.statusUpdatedAt, now: store.now) : "")
                                    .fixedSize()
                                ViewThatFits(in: .horizontal) {
                                    tabs(panels, selected, s)
                                    tabs(panels, selected, s, titles: false)
                                }
                            }
                            .padding(.horizontal, 14).frame(height: Dock.strip)
                        } else {
                            HStack(spacing: 0) {
                                ViewThatFits(in: .horizontal) {
                                    tabs(panels, selected, s)
                                    tabs(panels, selected, s, titles: false)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14).frame(height: Dock.strip)
                        }
                        Rectangle().fill(Hive.hair).frame(height: 1)
                        content(selected, for: s)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("No session selected", systemImage: "terminal",
                                               description: Text("Click a session in the overview."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                // a card like the session cards: white, rounded, soft shadow (hairline on dark)
                .background(Hive.card)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { if scheme == .dark { RoundedRectangle(cornerRadius: 16).strokeBorder(Hive.hair, lineWidth: 1) } }
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.05), radius: 1, y: 1)
                .shadow(color: scheme == .dark ? .clear : .black.opacity(0.05), radius: 12, y: 6)
                // whole points on all sides, otherwise the terminal text gets blurry
                .padding(.leading, inset(.leading)).padding(.trailing, inset(.trailing))
                .padding(.top, inset(.top)).padding(.bottom, inset(.bottom))
                .background { framed(panels[0]) }
            )
        case .split(let axis, let path, let children):
            let n = children.count
            return AnyView(
                DockSplit(axis: axis, shares: children.map(\.share),
                          onResize: { i, delta in
                              dock.change(persist: false) {
                                  $0.resize(split: path, before: children[i].index, after: children[i + 1].index, delta: delta)
                              }
                          },
                          onEnd: { dock.save() },
                          content: { i in
                              var e = edges
                              if axis == .horizontal {
                                  if i > 0 { e.remove(.leading) }
                                  if i < n - 1 { e.remove(.trailing) }
                              } else {
                                  if i > 0 { e.remove(.top) }
                                  if i < n - 1 { e.remove(.bottom) }
                              }
                              return node(children[i].node, s, header: header, edges: e)
                          })
            )
        }
    }

    /// The overview is moved by dragging its view switcher.
    private func overviewDragged(_ location: CGPoint, ended: Bool) {
        let item = Self.overviewItem
        let d = DockDrag(panel: .overview, title: item.title, symbol: item.symbol, location: location)
        if ended {
            drop(d)
            drag = nil
        } else {
            drag = d
        }
    }

    @ViewBuilder
    private func content(_ panel: DockPanel, for s: Session) -> some View {
        switch panel {
        case .overview:
            EmptyView()
        case .project:
            ProjectInfoView(cwd: store.cwd(s), sessionPrefix: SessionNaming.prefix(s.name), startEditing: editOnOpen)
                .id("\(s.name)#\(store.cwd(s) ?? "")")
        case .handover:
            HandoverView(name: s.name)
        case .notes:
            NotepadView(name: s.name).id(s.name)
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
