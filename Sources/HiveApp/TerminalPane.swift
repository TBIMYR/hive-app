import SwiftTerm
import SwiftUI
import HiveCore

struct TerminalPane: View {
    @EnvironmentObject private var store: StateStore
    let session: Session?
    @State private var message: String?
    @State private var showHandover = false

    var body: some View {
        VStack(spacing: 0) {
            if let s = session {
                HStack(spacing: 8) {
                    Circle().fill(store.color(for: s.groupKey)).frame(width: 8, height: 8)
                    Text(s.name).font(.hiveMono(14, .semibold))
                    Spacer(minLength: 4)
                    if let msg = message { Text(msg).font(.caption).foregroundStyle(Hive.muted) }
                    StatusLabel(status: store.status(s), since: s.alive == true ? dur(s.statusUpdatedAt, now: store.now) : "")
                    // Umschalter Terminal ↔ Handover, nur wenn es etwas zu zeigen gibt und die Session läuft
                    if s.hasHandover == true && store.tmux(s) != nil {
                        Button { showHandover.toggle() } label: {
                            Label(showHandover ? "Terminal" : "Handover",
                                  systemImage: showHandover ? "terminal" : "doc.text")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(showHandover ? "Back to the terminal" : "Read this session's handover")
                    }
                }
                .padding(.horizontal, 14).frame(height: 40)
                Rectangle().fill(Hive.hair).frame(height: 1)
                content(for: s)
            } else {
                ContentUnavailableView("No session selected", systemImage: "terminal",
                                       description: Text("Click a session on the left."))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Hive.card)
        .onChange(of: session?.name) { message = nil; showHandover = false }
        // Sprung-Taste: Handover zu, damit das Terminal den Fokus bekommen kann
        .onChange(of: store.focusRequest) { showHandover = false }
    }

    @ViewBuilder
    private func content(for s: Session) -> some View {
        if showHandover && s.hasHandover == true {
            HandoverView(name: s.name)
        } else if Tmux.path == nil {
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
            // offline: nur das Handover ist noch da, also gleich zeigen
            HandoverView(name: s.name)
        } else {
            ContentUnavailableView("Offline", systemImage: "moon.zzz",
                                   description: Text("No terminal and no handover."))
                .frame(maxHeight: .infinity)
        }
    }
}

/// In welches Terminal gerade getippt wird (tmux-Name, bis 3 s nach dem letzten Tastendruck).
/// Antwort-Knöpfe dieser Session sind solange gesperrt, damit nichts mit eigener Eingabe kollidiert.
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

    /// Antworten des Terminals selbst (Fokus rein/raus, Geräte-Abfragen) sind kein Tippen.
    nonisolated static func isTyping(_ data: ArraySlice<UInt8>) -> Bool {
        let s = String(decoding: data, as: UTF8.self)
        if s == "\u{1B}[I" || s == "\u{1B}[O" { return false }
        if ["\u{1B}[?", "\u{1B}[>", "\u{1B}]", "\u{1B}P"].contains(where: s.hasPrefix) { return false }
        // Cursor-Position „ESC [ 12;1 R“
        return !(s.hasPrefix("\u{1B}[") && s.hasSuffix("R") && s.count > 4)
    }
}

/// SwiftTerm-Terminal, das sich eine Fokus-Anfrage merkt, bis es in einem Fenster hängt. Nach einem
/// Session-Wechsel entsteht die View wegen `.id` neu und hat beim ersten updateNSView noch kein Fenster.
final class HiveTerminalView: LocalProcessTerminalView {
    var wantsFocus = false
    /// tmux-Session, an der das Terminal hängt
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Dateien und Bilder hineinziehen wie in iTerm: der Pfad wird getippt (Claude hängt Bilder dann an)
        registerForDraggedTypes([.fileURL, .png, .tiff])
        takeFocusIfWanted()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        var paths = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
            .map(\.path)
        // Bild ohne Datei (z. B. aus dem Browser): als PNG in einen Temp-Ordner legen
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

    /// Pfad wie iTerm mit Backslashes vor Leer- und Sonderzeichen
    static func shellEscaped(_ path: String) -> String {
        let special = Set(" \\'\"()[]{}&;|<>*?$`!#~")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }
}

/// SwiftTerm-Terminal, das sich per `tmux attach` an die Session hängt.
struct TmuxTerminal: NSViewRepresentable {
    let name: String
    /// Zähler aus dem Store; ändert er sich, holt sich das Terminal den Fokus
    let focusRequest: Int
    @Environment(\.colorScheme) private var scheme

    final class Coordinator {
        /// zuletzt bediente Fokus-Anfrage
        var focusSeen = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // Gleiche Töne wie die Karten im hive-Dashboard (--card / --ink).
    // SwiftTerm übernimmt Farben beim Setzen fest, darum bei jedem Wechsel des Modus neu setzen.
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
        // Proportionalschrift geht im Terminal-Raster nicht (jede Zelle so breit wie das breiteste
        // Zeichen, „C l a u d e“); zum Nachsehen: HIVE_TERM_FONT=system
        // Sonst wie ein übliches iTerm-Profil: MesloLGS NF 13 (Fett/Kursiv aus den Schnitten der Familie),
        // dünne Striche auf Retina (= ohne Font-Smoothing), Cursor als Strich ohne Blinken.
        view.font = ProcessInfo.processInfo.environment["HIVE_TERM_FONT"] == "system"
            ? NSFont.systemFont(ofSize: 13)
            : NSFont(name: "MesloLGS-NF-Regular", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.fontSmoothing = false
        view.getTerminal().setCursorStyle(.steadyBar)
        applyColors(view)
        hideScroller(view)
        view.startProcess(executable: Tmux.path!,
                          args: Tmux.attachArgs(name),
                          environment: Tmux.environmentList(),
                          execName: "tmux")
        // ein neues Terminal bekommt immer den Fokus (wie bisher), sobald es im Fenster hängt
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

    // Den Verlauf hält tmux, SwiftTerms eigener Scroller bleibt leer; er ist privat, darum über die Unteransichten
    private func hideScroller(_ view: HiveTerminalView) {
        view.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    static func dismantleNSView(_ nsView: HiveTerminalView, coordinator: Coordinator) {
        // beendet nur den attach-Prozess; die tmux-Session läuft weiter
        nsView.terminate()
    }
}
