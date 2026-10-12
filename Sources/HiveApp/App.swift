import AppKit
import SwiftUI
import HiveCore

// Without an app bundle (swift run) the window would otherwise have no keyboard focus and no menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The store belongs to the AppDelegate so the notification delegate is set up before the first window appears.
    let store = StateStore()
    let notes = NotesStore()
    let usage = UsageStore()
    let projects = ProjectInfoStore()

    let dock = DockStore()

    /// ⌘T: brings the selected session's notepad to the front with the cursor in it; once more goes back
    /// to what shares its tile (the terminal). In a collapsed tile it shows and hides the notepad on top.
    func toggleNotes() {
        guard let name = store.selected, let group = dock.layout.group(of: .notes) else { return }
        // collapsed: on top of the rest for the moment
        if group.collapsed {
            dock.peek = dock.peek == .notes ? nil : .notes
            if dock.peek == .notes { notes.focusRequest = name }
            return
        }
        if group.selected == .notes, let other = group.panels.first(where: { $0 != .notes }) {
            dock.change { $0.select(other) }
        } else {
            dock.change { $0.select(.notes) }
            notes.focusRequest = name
        }
    }

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
                .environmentObject(delegate.notes)
                .environmentObject(delegate.dock)
                .environmentObject(delegate.usage)
                .environmentObject(delegate.projects)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            // shortcuts here, not on the toolbar menu (those don't fire while the menu is closed)
            CommandGroup(replacing: .newItem) {
                Button("New Session") { delegate.store.newPreset = NewSessionPreset() }
                    .keyboardShortcut("n").disabled(Tmux.path == nil)
                Button("New Project…") { delegate.store.newProjectOpen = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // ⌘H only in hive: replaces "Hide hive" (this also drops "Hide Others" and "Show All")
            CommandGroup(replacing: .appVisibility) {
                Button("Jump to Waiting Session") { delegate.store.jumpToWaiting() }
                    .keyboardShortcut("h")
            }
            CommandGroup(after: .toolbar) {
                Button("Notes") { delegate.toggleNotes() }
                    .keyboardShortcut("t")
                Button("Reset Window Layout") { delegate.dock.reset() }
            }
        }
        // Hive → Settings… (⌘,)
        Settings {
            SettingsView().environmentObject(delegate.store)
        }
    }
}

/// Options of the app.
struct SettingsView: View {
    @EnvironmentObject private var store: StateStore
    @AppStorage(Notifier.soundKey) private var notifySound = true
    @AppStorage(Notifier.phoneKey) private var phonePush = false
    @AppStorage(Notifier.topicKey) private var topic = ""
    @AppStorage(Notifier.awayKey) private var awayMinutes = 5

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $store.keepAwake) {
                    Text("Keep the Mac awake while sessions work")
                    Text("Like Amphetamine: no idle sleep as long as at least one session is working, also in the background. The display may still turn off.")
                }
                Toggle(isOn: $notifySound) {
                    Text("Ping when a session needs you")
                    Text("Plays a sound with the notification. Banner style and badge are set in System Settings → Notifications → Hive.")
                }
            }
            Section {
                Toggle(isOn: $phonePush) {
                    Text("Push to the phone when I'm away")
                    Text("Sends \"needs you\" via ntfy once the Mac has had no mouse or keyboard input for a while. Install the ntfy app and subscribe to the topic below.")
                }
                if phonePush {
                    Stepper("Away after \(awayMinutes) min without input", value: $awayMinutes, in: 1...60)
                    LabeledContent("Topic") {
                        HStack(spacing: 8) {
                            Text(topic).font(.hiveMono(12)).textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(topic, forType: .string)
                            }
                            Button("Send test") {
                                Notifier.sendToPhone(topic: topic, title: "Hive", body: "Test: phone notifications work.")
                            }
                        }
                    }
                }
            }
            .onChange(of: phonePush) { _, on in if on && topic.isEmpty { topic = Notifier.newTopic() } }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: StateStore
    @EnvironmentObject private var usage: UsageStore
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

    /// Click: New Session; the arrow opens the menu with New Project.
    private var newSessionButton: some View {
        Menu {
            Button("New Session") { store.newPreset = NewSessionPreset() }.disabled(Tmux.path == nil)
            Button("New Project…") { store.newProjectOpen = true }
        } label: {
            Label("New", systemImage: "plus")
        } primaryAction: {
            if Tmux.path != nil { store.newPreset = NewSessionPreset() } else { store.newProjectOpen = true }
        }
        .help("New session in tmux (⌘N); the menu also has New Project (⇧⌘N)")
    }

    /// Keep-awake switch: cup with steam while it holds the Mac awake, empty cup while on but nothing works.
    private var awakeButton: some View {
        Button { store.keepAwake.toggle() } label: {
            Label("Keep Awake", systemImage: !store.keepAwake ? "moon.zzz" : store.holdingAwake ? "cup.and.heat.waves.fill" : "cup.and.saucer")
        }
        .help(!store.keepAwake ? "Mac may sleep while sessions work. Click to keep it awake."
              : store.holdingAwake ? "Keeping the Mac awake while sessions work. Click to turn off."
              : "Keeps the Mac awake as soon as a session works. Click to turn off.")
    }

    /// Plan usage, then Keep Awake and New Session at the right edge of the title bar; from macOS 26 a
    /// flexible spacer pushes them there. Without usage data the usage item is left out.
    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        let hasUsage = usage.current(now: store.now) != nil
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
            // usage forms its own section, apart from the session buttons
            if hasUsage {
                ToolbarItem(placement: .automatic) { UsageButton() }
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(placement: .automatic) { awakeButton }
            ToolbarItem(placement: .automatic) { newSessionButton }
        } else {
            if hasUsage { ToolbarItem(placement: .primaryAction) { UsageButton() } }
            ToolbarItem(placement: .primaryAction) { awakeButton }
            ToolbarItem(placement: .primaryAction) { newSessionButton }
        }
    }

    var body: some View {
        Workspace()
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
        .sheet(isPresented: $store.newProjectOpen) { NewProjectSheet() }
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
        .alert(store.forceQuitRequest?.title ?? "",
               isPresented: Binding(get: { store.forceQuitRequest != nil },
                                    set: { if !$0 { store.forceQuitRequest = nil } }),
               presenting: store.forceQuitRequest) { r in
            Button("Force Quit", role: .destructive) { store.forceQuit(r) }
            Button("Cancel", role: .cancel) {}
        } message: { r in
            Text(r.message)
        }
        .alert("Remove \(store.removeRequest?.name ?? "") from the list?",
               isPresented: Binding(get: { store.removeRequest != nil },
                                    set: { if !$0 { store.removeRequest = nil } }),
               presenting: store.removeRequest) { s in
            Button("Remove", role: .destructive) { store.remove(s) }
            Button("Cancel", role: .cancel) {}
        } message: { s in
            Text("Moves its handover to ~/.claude/handover/archive/\(s.name)/. Nothing is deleted; moving the file back brings the session back.")
        }
        .alert("Hive",
               isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(store.notice ?? "")
        }
    }
}
