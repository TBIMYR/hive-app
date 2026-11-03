import AppKit
import Carbon.HIToolbox
import SwiftUI

// Voice prototype for Hive: a small floating window next to the app, not part of it yet.
// Start with `sh tools/voice/hive-voice.sh` (builds, wraps it in an app bundle for the permissions and starts it).

@available(macOS 26, *)
struct PanelView: View {
    @ObservedObject var talk: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(talk.phase.rawValue).font(.headline)
                Spacer()
                // two buttons instead of a segmented picker: the picker set its value by itself on start
                ForEach(Output.allCases, id: \.self) { o in
                    Button(o.label) { if talk.output != o { talk.switchOutput() } }
                        .controlSize(.small).disabled(talk.output == o)
                }
            }
            Text(talk.voiceName).font(.caption).foregroundStyle(.secondary)
            if !talk.heard.isEmpty { Text("You: \(talk.heard)").font(.callout).lineLimit(3) }
            if !talk.answer.isEmpty { Text(talk.answer).font(.callout).foregroundStyle(.secondary).lineLimit(5) }
            if let p = talk.pending {
                Text("Waiting for your yes – to \(p.to): \(p.text)").font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
            if let m = talk.sending {
                Text("Sending to \(m.to) in a moment: \(m.text) – press ⌃⌥Space to stop").font(.caption).foregroundStyle(.orange).lineLimit(3)
            } else if let f = talk.focus {
                Text("Focus: \(f)").font(.caption).foregroundStyle(.secondary)
            }
            if let problem = talk.problem { Text(problem).font(.caption).foregroundStyle(.red).lineLimit(3) }
            HStack {
                Text("Hold ⌃⌥Space to talk · ⌃⌥V switches the voice").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    var color: Color {
        switch talk.phase {
        case .listening: .red
        case .thinking, .countdown: .orange
        case .speaking: .green
        case .starting: .gray
        case .idle: .blue
        }
    }
}

@available(macOS 26, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let talk = Conversation(config: Config.parse(Array(CommandLine.arguments.dropFirst())))
    var panel: NSPanel?
    var hotkeys: Hotkeys?

    func applicationDidFinishLaunching(_ n: Notification) {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Hive Voice"
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: PanelView(talk: talk))
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameTopLeftPoint(NSPoint(x: screen.maxX - 400, y: screen.maxY - 20))
        }
        p.orderFrontRegardless()
        panel = p

        let ctrlOpt = controlKey | optionKey
        hotkeys = Hotkeys([
            .init(id: 1, code: kVK_Space, modifiers: ctrlOpt, onPress: { [talk] in talk.talkPressed() },
                  onRelease: { [talk] in talk.talkReleased() }),
            .init(id: 2, code: kVK_ANSI_V, modifiers: ctrlOpt, onPress: { [talk] in talk.switchOutput() }),
            .init(id: 3, code: kVK_ANSI_Q, modifiers: ctrlOpt, onPress: { NSApp.terminate(nil) }),
        ])
        Task { await talk.prepare() }
        if talk.config.textMode { readTyped() }
        log("hold ⌃⌥Space to talk, ⌃⌥V switches the voice, ⌃⌥Q quits")
    }

    /// --text: every line from stdin counts as something said.
    func readTyped() {
        Thread.detachNewThread { [talk] in
            while let line = readLine() {
                let text = line.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                DispatchQueue.main.async { MainActor.assumeIsolated { talk.heard = text; talk.say(text) } }
            }
        }
    }
}

@available(macOS 26, *)
func runApp() {
    MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    }
}

if #available(macOS 26, *) { runApp() } else { print("hive-voice needs macOS 26 (SpeechAnalyzer)") }
