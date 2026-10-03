import AppKit
import SwiftUI
import HiveCore

// Ohne App-Bundle (swift run) wäre das Fenster sonst ohne Tastaturfokus und Menüleiste.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = StateStore()

    var body: some Scene {
        WindowGroup("hive") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1440, height: 860)
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    // `--select <name>` wählt beim Start eine Session (zum Ausprobieren)
    @State private var selected: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--select"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    @State private var newPreset: NewSessionPreset?

    var body: some View {
        // Übersicht ⅔, Terminal fest ⅓ (wie besprochen; die Übersicht soll Platz behalten)
        GeometryReader { geo in
            HStack(spacing: 0) {
                OverviewView(selected: $selected, newPreset: $newPreset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Hive.hair2).frame(width: 1)
                TerminalPane(session: store.displaySessions.first { $0.name == selected })
                    // ganze Punkte: sonst liegt das Terminal zwischen zwei Pixeln und der Text wird unscharf
                    .frame(width: max(340, (geo.size.width / 3).rounded()))
                    .frame(maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newPreset = NewSessionPreset() } label: { Label("Neue Session", systemImage: "plus") }
                    .disabled(Tmux.path == nil)
                    .help("Neue Session in tmux starten (⌘N)")
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $newPreset) { preset in
            NewSessionSheet(preset: preset) { name in
                selected = name
                store.refreshSoon()
            }
        }
    }
}
