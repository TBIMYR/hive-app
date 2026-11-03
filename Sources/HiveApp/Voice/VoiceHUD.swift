import AppKit
import Combine
import SwiftUI

/// Small pill at the bottom center of the screen while Hive listens, thinks, speaks or is about to send,
/// also when Hive is in the background. Fades out a few seconds after the conversation went quiet.
@available(macOS 26, *)
@MainActor
final class VoiceHUD {
    static let lingerAfter: TimeInterval = 4

    private let voice: VoiceController
    private var panel: NSPanel?
    private var watch: AnyCancellable?
    private var hide: Task<Void, Never>?

    init(voice: VoiceController) {
        self.voice = voice
        watch = voice.$phase.combineLatest(voice.$sending).receive(on: RunLoop.main).sink { [weak self] phase, sending in
            self?.update(active: (phase != .idle && phase != .off) || sending != nil, off: phase == .off)
        }
    }

    private func update(active: Bool, off: Bool) {
        hide?.cancel()
        if active { show(); return }
        guard panel != nil else { return }
        if off { close(); return }
        hide = Task {
            try? await Task.sleep(for: .seconds(Self.lingerAfter))
            if !Task.isCancelled { close() }
        }
    }

    private func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.ignoresMouseEvents = true
            p.contentView = NSHostingView(rootView: VoicePill(voice: voice))
            panel = p
        }
        guard let p = panel, let screen = NSScreen.main?.visibleFrame else { return }
        p.setFrameOrigin(NSPoint(x: screen.midX - p.frame.width / 2, y: screen.minY + 24))
        p.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
    }
}

@available(macOS 26, *)
struct VoicePill: View {
    @ObservedObject var voice: VoiceController

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: voice.phase == .listening || voice.phase == .thinking)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line).font(.system(size: 13)).foregroundStyle(Hive.ink).lineLimit(3)
                    if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(Hive.ink2).lineLimit(2) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: 480, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .frame(width: 520, height: 120, alignment: .bottom)
    }

    private var icon: String {
        switch voice.phase {
        case .listening: "mic.fill"
        case .thinking: "ellipsis"
        case .speaking: "waveform"
        case .countdown: "paperplane"
        case .idle, .off: "checkmark"
        }
    }

    private var color: Color {
        switch voice.phase {
        case .listening: Hive.need
        case .countdown: Hive.wait
        default: Hive.ink2
        }
    }

    private var line: String {
        if let m = voice.sending { return "To \(m.to): \(m.text)" }
        switch voice.phase {
        case .listening: return voice.heard.isEmpty ? "Listening …" : voice.heard
        case .thinking: return voice.heard.isEmpty ? "Thinking …" : voice.heard
        default: return voice.answer.isEmpty ? voice.heard : voice.answer
        }
    }

    private var sub: String? {
        if voice.sending != nil { return "Sending in a moment – press \(VoiceSettings.trigger.hint.replacingOccurrences(of: "Hold ", with: "")) to stop" }
        if let p = voice.pending { return "Waiting for your yes – to \(p.to): \(p.text)" }
        if let problem = voice.problem { return problem }
        if let f = voice.focus, voice.phase == .speaking { return "About \(f)" }
        return nil
    }
}
