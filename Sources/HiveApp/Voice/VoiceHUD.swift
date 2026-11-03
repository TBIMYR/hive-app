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
            let size = NSSize(width: VoicePill.width + 2 * VoicePill.margin, height: 240)
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
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
        p.setFrameOrigin(NSPoint(x: (screen.midX - p.frame.width / 2).rounded(), y: screen.minY + 8))
        p.orderFrontRegardless()
    }

    private func close() {
        panel?.orderOut(nil)
    }
}

@available(macOS 26, *)
struct VoicePill: View {
    @ObservedObject var voice: VoiceController
    static let width: CGFloat = 460
    /// room around the card for its shadow (like FloatingCard)
    static let margin: CGFloat = 24

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PulseDot(color: color, pulsing: voice.phase == .listening || voice.phase == .thinking)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Hive.muted)
                Spacer(minLength: 0)
                Text(VoiceSettings.trigger.hint).font(.system(size: 11)).foregroundStyle(Hive.idle)
            }
            if !line.isEmpty {
                Text(line).font(.system(size: 14)).foregroundStyle(Hive.ink).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let sub {
                Text(sub).font(.system(size: 12)).foregroundStyle(Hive.muted).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: Self.width, alignment: .leading)
        .background { CardSurface(shape: shape, glow: voice.phase == .listening) }
        .padding(Self.margin)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .animation(.easeOut(duration: 0.15), value: voice.phase)
    }

    private var title: String {
        if let m = voice.sending { return "To \(m.to) in a moment" }
        switch voice.phase {
        case .listening: return voice.handsFree ? "Listening – just answer" : "Listening"
        case .thinking: return "Thinking"
        case .countdown: return "Sending"
        default: return voice.focus.map { "Hive · \($0)" } ?? "Hive"
        }
    }

    private var color: Color {
        switch voice.phase {
        case .listening: Hive.need
        case .thinking: Hive.idle
        case .speaking: Hive.busy
        case .countdown: Hive.wait
        case .idle, .off: Hive.idle
        }
    }

    private var line: String {
        if let m = voice.sending { return m.text }
        switch voice.phase {
        case .listening, .thinking: return voice.heard
        default: return voice.answer.isEmpty ? voice.heard : voice.answer
        }
    }

    private var sub: String? {
        if voice.sending != nil { return "Press \(VoiceSettings.trigger.hint.replacingOccurrences(of: "Hold ", with: "")) to stop" }
        if let p = voice.pending { return "Waiting for your yes – to \(p.to): \(p.text)" }
        return voice.problem
    }
}

/// Status dot like on the cards; breathes while Hive listens or thinks.
struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    @State private var on = false

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(pulsing && on ? 0.35 : 1)
            .animation(pulsing ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { on = true }
            .onChange(of: pulsing) { _, p in on = p }
    }
}
