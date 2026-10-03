import AppKit
import SwiftUI
import HiveCore

// Ohne App-Bundle (swift run) wäre das Fenster sonst ohne Tastaturfokus und Menüleiste.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Der Store gehört dem AppDelegate, damit der Mitteilungs-Delegate schon vor dem ersten Fenster steht.
    let store = StateStore()

    func applicationWillFinishLaunching(_ notification: Notification) {
        store.notifier.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct HiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Hive") {
            ContentView()
                .environmentObject(delegate.store)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            // ⌘H nur in hive: ersetzt „Hide hive“ (dazu fallen „Hide Others“ und „Show All“ weg)
            CommandGroup(replacing: .appVisibility) {
                Button("Jump to Waiting Session") { delegate.store.jumpToWaiting() }
                    .keyboardShortcut("h")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    /// Breite des Terminals in Punkten, per Ziehen an der Grenze geändert; 0 = Standard (⅓ des Fensters)
    @AppStorage("terminalWidth") private var terminalWidth: Double = 0
    @State private var dragStart: Double?

    private static let minTerminal: Double = 340
    private static let minOverview: Double = 420

    /// Breite des Terminals für die Fensterbreite, begrenzt und auf ganze Punkte gerundet
    /// (sonst liegt das Terminal zwischen zwei Pixeln und der Text wird unscharf).
    private func width(for total: Double, wanted: Double) -> Double {
        let w = wanted > 0 ? wanted : total / 3
        return min(max(w, Self.minTerminal), max(Self.minTerminal, total - Self.minOverview)).rounded()
    }

    var body: some View {
        GeometryReader { geo in
            let total = Double(geo.size.width)
            let w = width(for: total, wanted: terminalWidth)
            HStack(spacing: 0) {
                OverviewView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TerminalPane(session: store.displaySessions.first { $0.name == store.selected })
                    .frame(width: w)
                    .frame(maxHeight: .infinity)
            }
            // unsichtbarer Griff auf der Grenze: Ziehen ändert die Breite des Terminals
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 9).frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .offset(x: total - w - 4.5)
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                let start = dragStart ?? w
                                dragStart = start
                                terminalWidth = width(for: total, wanted: start - Double(v.translation.width))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
        }
        // statt des Fenstertitels: Signet und Wortmarke links in der Titelleiste
        .onAppear { NSApp.windows.forEach { $0.titleVisibility = .hidden } }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    ZStack {
                        HiveMark().fill(Hive.ink)
                        HiveMark().stroke(Hive.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    }
                    .frame(width: 15, height: 17)
                    Text("Hive").font(.system(size: 15, weight: .bold)).kerning(-0.2).foregroundStyle(Hive.ink)
                }
                .padding(.leading, 4)
            }
            ToolbarItem(placement: .automatic) {
                Button { store.newPreset = NewSessionPreset() } label: { Label("New Session", systemImage: "plus") }
                    .disabled(Tmux.path == nil)
                    .help("Start a new session in tmux (⌘N)")
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $store.newPreset) { preset in
            NewSessionSheet(preset: preset) { name in
                store.selected = name
                store.refreshSoon()
            }
        }
    }
}
