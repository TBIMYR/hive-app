import AppKit
import SwiftUI

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

    var body: some View {
        HSplitView {
            OverviewView(selected: $selected)
                .frame(minWidth: 420, idealWidth: 960, maxWidth: .infinity, maxHeight: .infinity)
            TerminalPane(session: store.sessions.first { $0.name == selected })
                .frame(minWidth: 360, idealWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
