import AppKit
import SwiftUI
import HiveCore

// Without an app bundle (swift run) the window would otherwise have no keyboard focus and no menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The store belongs to the AppDelegate so the notification delegate is set up before the first window appears.
    let store = StateStore()
    let todos = TodoStore()

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
    @AppStorage("todoVisible") private var todoVisible = false

    var body: some Scene {
        WindowGroup("Hive") {
            ContentView()
                .environmentObject(delegate.store)
                .environmentObject(delegate.todos)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            // ⌘H only in hive: replaces "Hide hive" (this also drops "Hide Others" and "Show All")
            CommandGroup(replacing: .appVisibility) {
                Button("Jump to Waiting Session") { delegate.store.jumpToWaiting() }
                    .keyboardShortcut("h")
            }
            // in the View menu, checked as long as the card is visible
            CommandGroup(after: .toolbar) {
                Toggle("Todo List", isOn: $todoVisible)
                    .keyboardShortcut("t")
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    /// Width of the terminal in points, changed by dragging the divider; 0 = default (⅓ of the window)
    @AppStorage("terminalWidth") private var terminalWidth: Double = 0
    @AppStorage("todoVisible") private var todoVisible = false
    @State private var dragStart: Double?

    private static let minTerminal: Double = 340
    private static let minOverview: Double = 420

    /// Terminal width for the window width, clamped and rounded to whole points
    /// (otherwise the terminal sits between two pixels and the text gets blurry).
    private func width(for total: Double, wanted: Double) -> Double {
        let w = wanted > 0 ? wanted : total / 3
        return min(max(w, Self.minTerminal), max(Self.minTerminal, total - Self.minOverview)).rounded()
    }

    /// Mark and wordmark on the left of the title bar
    private var brandLabel: some View {
        HStack(spacing: 8) {
            ZStack {
                HiveMark().fill(Hive.ink)
                HiveMark().stroke(Hive.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            .frame(width: 15, height: 17)
            Text("Hive").font(.system(size: 15, weight: .medium)).kerning(-0.1).foregroundStyle(Hive.ink)
        }
        .padding(.leading, 4)
    }

    @ToolbarContentBuilder
    private var brand: some ToolbarContent {
        // from macOS 26 toolbar items otherwise get a glass background; the logo stands free
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { brandLabel }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { brandLabel }
        }
    }

    private var todoButton: some View {
        Button { todoVisible.toggle() } label: { Label("Todo List", systemImage: "checklist") }
            .help(todoVisible ? "Hide the todo list (⌘T)" : "Show the todo list (⌘T)")
    }

    private var newSessionButton: some View {
        Button { store.newPreset = NewSessionPreset() } label: { Label("New Session", systemImage: "plus") }
            .disabled(Tmux.path == nil)
            .help("Start a new session in tmux (⌘N)")
            .keyboardShortcut("n")
    }

    /// Todo and New Session at the right edge of the title bar; from macOS 26 a flexible spacer pushes them there
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) { todoButton }
            ToolbarItem(placement: .automatic) { newSessionButton }
        } else {
            ToolbarItem(placement: .primaryAction) { todoButton }
            ToolbarItem(placement: .primaryAction) { newSessionButton }
        }
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
            // invisible handle on the divider: dragging changes the terminal's width
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
            // floating todo card, by default top right in the overview
            .overlay(alignment: .topLeading) {
                if todoVisible {
                    TodoPanel(bounds: geo.size,
                              defaultOrigin: CGPoint(x: total - w - TodoPanel.defaultSize.width - 26, y: 64),
                              visible: $todoVisible)
                }
            }
        }
        // instead of the window title: mark and wordmark on the left of the title bar
        .onAppear { NSApp.windows.forEach { $0.titleVisibility = .hidden } }
        .toolbar {
            brand
            actions
        }
        .sheet(item: $store.newPreset) { preset in
            NewSessionSheet(preset: preset) { name in
                store.selected = name
                store.refreshSoon()
            }
        }
        // confirmation for Close…/Restart… from the right-click menu
        .alert(store.closeRequest?.title ?? "",
               isPresented: Binding(get: { store.closeRequest != nil },
                                    set: { if !$0 { store.closeRequest = nil } }),
               presenting: store.closeRequest) { r in
            Button(r.restart ? "Restart" : "Close", role: .destructive) { store.close(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text(r.message)
        }
        .alert("Hive",
               isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.notice ?? "")
        }
    }
}
