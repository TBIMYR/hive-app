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
                    Text(s.name).font(.system(.headline, design: .monospaced))
                    StatusPill(status: Status(s))
                    Spacer()
                    if let msg = message { Text(msg).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                Divider()
                content(for: s)
            } else {
                ContentUnavailableView("Keine Session gewählt", systemImage: "terminal",
                                       description: Text("Links eine Kachel anklicken."))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: session?.name) { message = nil }
    }

    @ViewBuilder
    private func content(for s: Session) -> some View {
        if Tmux.path == nil {
            ContentUnavailableView("tmux fehlt", systemImage: "exclamationmark.triangle",
                                   description: Text("brew install tmux"))
        } else if Tmux.hasSession(s.name) {
            TmuxTerminal(name: s.name).id(s.name)
        } else if s.alive == true {
            VStack(spacing: 12) {
                ContentUnavailableView("Läuft in iTerm", systemImage: "macwindow",
                                       description: Text("Diese Session hat keine tmux-Session. Neue Sessions über „Neue Session“ starten."))
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
        }
    }
}

/// SwiftTerm-Terminal, das sich per `tmux attach` an die Session hängt.
struct TmuxTerminal: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.startProcess(executable: Tmux.path!,
                          args: ["attach-session", "-t", Tmux.target(name)],
                          environment: Tmux.environmentList(),
                          execName: "tmux")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // beendet nur den attach-Prozess; die tmux-Session läuft weiter
        nsView.terminate()
    }
}
