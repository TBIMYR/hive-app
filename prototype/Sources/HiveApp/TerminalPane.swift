import SwiftTerm
import SwiftUI

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
                    // Toggle terminal ↔ handover, only if there is something to show and the session is running
                    if s.hasHandover == true && store.tmuxNames.contains(s.name) {
                        Button { showHandover.toggle() } label: {
                            Label(showHandover ? "Terminal" : "Handover",
                                  systemImage: showHandover ? "terminal" : "doc.text")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help(showHandover ? "Back to terminal" : "Read this session's handover")
                    }
                }
                .padding(.horizontal, 14).frame(height: 40)
                Rectangle().fill(Hive.hair).frame(height: 1)
                content(for: s)
            } else {
                ContentUnavailableView("No session selected", systemImage: "terminal",
                                       description: Text("Click a card on the left."))
                    .frame(maxHeight: .infinity)
            }
        }
        .background(Hive.card)
        .onChange(of: session?.name) { message = nil; showHandover = false }
    }

    @ViewBuilder
    private func content(for s: Session) -> some View {
        if showHandover && s.hasHandover == true {
            HandoverView(name: s.name)
        } else if Tmux.path == nil {
            ContentUnavailableView("tmux missing", systemImage: "exclamationmark.triangle",
                                   description: Text("brew install tmux"))
                .frame(maxHeight: .infinity)
        } else if store.tmuxNames.contains(s.name) {
            TmuxTerminal(name: s.name).id(s.name)
                .padding(.horizontal, 28).padding(.top, 6)
        } else if s.alive == true {
            VStack(spacing: 12) {
                ContentUnavailableView("Running in iTerm", systemImage: "macwindow",
                                       description: Text("This session has no tmux session. Start new sessions via the \"New session\" card or ⌘N."))
                if s.kind != "bg" {
                    Button("Show in iTerm") {
                        Task { message = await store.focusInITerm(s) ?? "→ iTerm" }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else if s.hasHandover == true {
            // offline: only the handover is left, so show it right away
            HandoverView(name: s.name)
        } else {
            ContentUnavailableView("Offline", systemImage: "moon.zzz",
                                   description: Text("No terminal and no handover."))
                .frame(maxHeight: .infinity)
        }
    }
}

/// SwiftTerm terminal that attaches to the session via `tmux attach`.
struct TmuxTerminal: NSViewRepresentable {
    let name: String
    @Environment(\.colorScheme) private var scheme

    // Same tones as the cards in the hive dashboard (--card / --ink).
    // SwiftTerm fixes colors when they are set, so set them again on every appearance change.
    private func applyColors(_ view: LocalProcessTerminalView) {
        let dark = scheme == .dark
        view.nativeBackgroundColor = NSColor(hex: dark ? 0x141414 : 0xFFFFFF)
        view.nativeForegroundColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.caretColor = NSColor(hex: dark ? 0xF5F5F4 : 0x0B0B0B)
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        // A proportional font does not work in the terminal grid (every cell as wide as the widest
        // character, "C l a u d e"); to see for yourself: HIVE_TERM_FONT=system
        // Otherwise like a typical iTerm profile: MesloLGS NF 13 (bold/italic from the family's faces),
        // thin strokes on Retina (= no font smoothing), bar cursor without blinking.
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
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        applyColors(nsView)
        hideScroller(nsView)
    }

    // tmux keeps the scrollback, SwiftTerm's own scroller stays empty; it is private, hence via the subviews
    private func hideScroller(_ view: LocalProcessTerminalView) {
        view.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: ()) {
        // only ends the attach process; the tmux session keeps running
        nsView.terminate()
    }
}
