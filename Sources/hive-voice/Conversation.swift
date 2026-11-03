import Foundation
import HiveCore
import VoiceKit

/// Push to talk → recognition → Claude → voice, plus the confirmation gate for passing tasks on.
@available(macOS 26, *)
@MainActor
final class Conversation: ObservableObject {
    enum Phase: String { case starting = "Starting …", idle = "Ready", listening = "Listening …", thinking = "Thinking …", speaking = "Speaking" }

    @Published var phase = Phase.starting
    @Published var heard = ""
    @Published var answer = ""
    @Published var output: Output
    @Published var pending: Handoff.Message?
    @Published var problem: String?

    let config: Config
    private let listener: Listener
    private let brain: Brain
    private let apple: AppleSpeaker
    private let eleven: ElevenSpeaker
    private var handoff = Handoff()
    private var notes: [String] = []         // app events for the next turn ("[HIVE] sent to …")
    private var sessions: [Session] = []
    private var discard = false              // barge-in during an answer: drop the rest of it
    private var queued: String?
    private var filter = SpokenFilter()
    private var splitter = SentenceSplitter()
    private var asked = Date()
    private var firstSentence = true

    init(config: Config) {
        self.config = config
        output = config.output
        listener = Listener(locale: config.locale)
        brain = Brain(model: config.model)
        apple = AppleSpeaker(locale: config.locale)
        eleven = ElevenSpeaker(voiceID: config.elevenVoice, model: config.elevenModel)
        if output == .eleven, !eleven.hasKey {
            output = .apple
            problem = "No ElevenLabs key – using the macOS voice"
        }
        listener.onPartial = { [weak self] in self?.heard = $0 }
        eleven.onError = { [weak self] msg in self?.apple.say(msg) }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var speaker: Speaker { output == .apple ? apple : eleven }
    var voiceName: String { speaker.name }

    func prepare() async {
        brain.start()
        log("output: \(output.label) – \(voiceName)")
        if !config.textMode {
            do { try await listener.prepare() } catch {
                problem = error.localizedDescription
                log("speech recognition: \(error.localizedDescription)")
            }
        }
        phase = .idle
    }

    // MARK: push to talk

    func talkPressed() {
        stopSpeaking()
        guard phase != .starting else { return }
        heard = ""
        phase = .listening
        Task {
            do { try await listener.start() } catch {
                problem = error.localizedDescription
                phase = .idle
            }
        }
    }

    func talkReleased() {
        guard phase == .listening else { return }
        Task {
            let text = await listener.stop()
            heard = text
            if text.isEmpty { phase = .idle; return }
            say(text)
        }
    }

    func switchOutput() {
        stopSpeaking()
        output = output.toggled
        if output == .eleven, !eleven.hasKey { problem = "No ElevenLabs key – see the terminal" }
        log("output: \(output.label) – \(voiceName)")
        speaker.say(output == .apple ? "Jetzt mit der Mac-Stimme." : "Jetzt mit ElevenLabs.")
    }

    /// Barge-in: silence at once, and whatever Claude still sends for this answer is dropped.
    private func stopSpeaking() {
        apple.stop()
        eleven.stop()
        if brain.isBusy { discard = true }
    }

    // MARK: one turn

    func say(_ text: String) {
        guard !brain.isBusy else { queued = text; return }
        phase = .thinking
        answer = ""
        discard = false
        filter = SpokenFilter()
        splitter = SentenceSplitter()
        firstSentence = true
        Task {
            let state = await Task.detached { StateBuilder.build().sessions }.value
            sessions = state
            var prompt = "[HIVE STATE \(Date().formatted(date: .omitted, time: .shortened))]\n\(StateSummary.lines(state))\n"
            if let p = handoff.pending { prompt += "[HIVE] proposal waiting for a yes: to \(p.to): \(p.text)\n" }
            prompt += notes.map { "[HIVE] \($0)\n" }.joined()
            notes = []
            prompt += "\n[USER] \(text)"
            asked = Date()
            log("you: \(text)")
            brain.ask(prompt, delta: { self.streamed($0) }, done: { self.answered($0) })
        }
    }

    private func streamed(_ delta: String) {
        guard !discard else { return }
        let visible = filter.feed(delta)
        answer += visible
        speak(splitter.feed(visible))
    }

    private func answered(_ full: String) {
        if !discard {
            speak(splitter.feed(filter.finish()) + splitter.flush())
            let (spoken, directives) = Directives.parse(full)
            answer = spoken
            log("claude: \(full.replacingOccurrences(of: "\n", with: " ⏎ "))")
            if let msg = handoff.apply(directives) { deliver(msg) }
        } else {
            // the user interrupted: the answer was not heard, so any proposal in it does not count
            notes.append("the user interrupted your last answer; they did not hear it to the end")
        }
        pending = handoff.pending
        discard = false
        if let next = queued { queued = nil; say(next) }
    }

    private func speak(_ sentences: [String]) {
        for s in sentences {
            if firstSentence {
                firstSentence = false
                log(String(format: "first sentence after %.2fs", Date().timeIntervalSince(asked)))
            }
            speaker.say(s)
        }
    }

    private func deliver(_ msg: Handoff.Message) {
        if let why = Delivery.send(msg.text, to: msg.to, sessions: sessions) {
            log("not sent to \(msg.to): \(why)")
            notes.append("sending to \(msg.to) FAILED: \(why)")
            speaker.say(why)
        } else {
            log("sent to \(msg.to): \(msg.text)")
            notes.append("message delivered to \(msg.to): \(msg.text)")
            speaker.say("Ist an \(msg.to) raus.")
        }
    }

    private func tick() {
        switch phase {
        case .thinking where speaker.isSpeaking: phase = .speaking
        case .speaking where !speaker.isSpeaking && !brain.isBusy: phase = .idle
        default: break
        }
    }
}
