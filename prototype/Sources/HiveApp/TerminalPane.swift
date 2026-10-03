import SwiftTerm
import SwiftUI

struct TerminalPane: View {
    @EnvironmentObject private var store: StateStore
    let session: Session?
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            if let s = session {
                HStack(spacing: 8) {
                    Circle().fill(store.color(for: s.groupKey)).frame(width: 8, height: 8)
                    Text(s.name).font(.hiveMono(14, .semibold))
                    Spacer(minLength: 4)
                    if let msg = message { Text(msg).font(.caption).foregroundStyle(Hive.muted) }
                    StatusLabel(status: store.status(s), since: s.alive == true ? dur(s.statusUpdatedAt, now: store.now) : "")
                }
                .padding(.horizontal, 14).frame(height: 40)
                Rectangle().fill(Hive.hair).frame(height: 1)
                content(for: s)
            } else {
                ContentUnavailableView("Keine Session gewählt", systemImage: "terminal",
                                       description: Text("Links eine Karte anklicken."))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Hive.card)
        .onChange(of: session?.name) { message = nil }
    }

    @ViewBuilder
    private func content(for s: Session) -> some View {
        if Tmux.path == nil {
            ContentUnavailableView("tmux fehlt", systemImage: "exclamationmark.triangle",
                                   description: Text("brew install tmux"))
                .frame(maxHeight: .infinity)
        } else if store.tmuxNames.contains(s.name) {
            TmuxTerminal(name: s.name).id(s.name)
                .padding(.horizontal, 18).padding(.top, 6)
        } else if s.alive == true {
            VStack(spacing: 12) {
                ContentUnavailableView("Läuft in iTerm", systemImage: "macwindow",
                                       description: Text("Diese Session hat keine tmux-Session. Neue Sessions über die Karte „Neue Session“ oder ⌘N starten."))
                if s.kind != "bg" {
                    Button("In iTerm zeigen") {
                        Task { message = await store.focusInITerm(s) ?? "→ iTerm" }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            ContentUnavailableView("Offline", systemImage: "moon.zzz",
                                   description: Text("Nur das Handover ist noch da."))
                .frame(maxHeight: .infinity)
        }
    }
}

/// SwiftTerm-Terminal, das sich per `tmux attach` an die Session hängt.
struct TmuxTerminal: NSViewRepresentable {
    let name: String
    @Environment(\.colorScheme) private var scheme

    // Gleiche Töne wie die Karten im hive-Dashboard (--card / --ink).
    // SwiftTerm übernimmt Farben beim Setzen fest, darum bei jedem Wechsel des Modus neu setzen.
    private func applyColors(_ view: LocalProcessTerminalView) {
        let dark = scheme == .dark
        view.nativeBackgroundColor = NSColor(hex: dark ? 0x141414 : 0xFFFFFF)
        view.nativeForegroundColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.caretColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        // Proportionalschrift geht im Terminal-Raster nicht (jede Zelle so breit wie das breiteste
        // Zeichen, „C l a u d e“); zum Nachsehen: HIVE_TERM_FONT=system
        view.font = ProcessInfo.processInfo.environment["HIVE_TERM_FONT"] == "system"
            ? NSFont.systemFont(ofSize: 13)
            : NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        applyColors(view)
        hideScroller(view)
        view.startProcess(executable: Tmux.path!,
                          args: Tmux.attachArgs(name),
                          environment: Tmux.environmentList(),
                          execName: "tmux")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyColors(nsView)
        hideScroller(nsView)
    }

    // Den Verlauf hält tmux, SwiftTerms eigener Scroller bleibt leer; er ist privat, darum über die Unteransichten
    private func hideScroller(_ view: LocalProcessTerminalView) {
        view.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // beendet nur den attach-Prozess; die tmux-Session läuft weiter
        nsView.terminate()
    }
}
