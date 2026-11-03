import Foundation
import HiveCore
import VoiceKit

/// Push to talk → recognition → Claude → voice, plus the confirmation gate for passing tasks on.
/// Hive also speaks up by itself when a session starts waiting for the user; that session is then in focus,
/// so a plain "ja" answers it.
@available(macOS 26, *)
@MainActor
final class Conversation: ObservableObject {
    enum Phase: String {
        case starting = "Starting …", idle = "Ready", listening = "Listening …", thinking = "Thinking …", speaking = "Speaking"
        case countdown = "Sending – press to stop"
    }

    /// pause after a quick reply has been read out, in which pressing the hotkey still stops it
    static let stopWindow: Duration = .seconds(2.5)
    static let pollEvery: TimeInterval = 4

    @Published var phase = Phase.starting { didSet { if phase != oldValue { log("· \(phase.rawValue)") } } }
    @Published var heard = ""
    @Published var answer = ""
    @Published var output: Output
    @Published var pending: Handoff.Message?
    @Published var problem: String?
    @Published var focus: String?
    @Published var sending: Handoff.Message?

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
    private var inTurn = false
    private var tracker = AttentionTracker()
    private var polled = false
    private var announce: [String: String] = [:]   // session → why it needs the user, not yet told
    private var countdown: Task<Void, Never>?
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
        Timer.scheduledTimer(withTimeInterval: Self.pollEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
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
        stopCountdown()
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

    func say(_ text: String) { turn(user: text) }

    private func turn(user text: String?, event: String? = nil) {
        guard !inTurn else { if let text { queued = text }; return }
        inTurn = true
        phase = .thinking
        answer = ""
        discard = false
        filter = SpokenFilter()
        splitter = SentenceSplitter()
        firstSentence = true
        Task {
            let (state, dialogs) = await Task.detached { () -> ([Session], [String: String]) in
                let all = StateBuilder.build().sessions
                // the choices a waiting session shows, so "ja" can become the right option
                var d: [String: String] = [:]
                for name in Attention.needs(all).keys { d[name] = Delivery.dialog(name).map(DialogReply.describe) }
                return (all, d)
            }.value
            sessions = state
            var prompt = "[HIVE STATE \(Date().formatted(date: .omitted, time: .shortened))]\n\(StateSummary.lines(state))\n"
            for (name, options) in dialogs.sorted(by: { $0.key < $1.key }) {
                prompt += "[HIVE] \(name) shows a choice dialog: \(options)\n"
            }
            if let p = handoff.pending { prompt += "[HIVE] proposal waiting for a yes: to \(p.to): \(p.text)\n" }
            if let focus { prompt += "[HIVE] focus: \(focus) (you announced it last; a reply without a name means this session)\n" }
            prompt += notes.map { "[HIVE] \($0)\n" }.joined()
            notes = []
            if let event { prompt += "\n[HIVE EVENT] \(event)" }
            if let text { prompt += "\n[USER] \(text)" }
            asked = Date()
            log(text.map { "you: \($0)" } ?? "event: \(event ?? "")")
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
            switch handoff.apply(directives, waiting: Set(Attention.needs(sessions).keys)) {
            case let .send(msg): deliver(msg)
            case let .countdown(msg): startCountdown(msg)
            case nil: break
            }
        } else {
            // the user interrupted: the answer was not heard, so any proposal in it does not count
            notes.append("the user interrupted your last answer; they did not hear it to the end")
        }
        pending = handoff.pending
        discard = false
        inTurn = false
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

    // MARK: quick reply with a pause for "stop"

    private func startCountdown(_ msg: Handoff.Message) {
        sending = msg
        countdown = Task {
            while speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
            phase = .countdown
            try? await Task.sleep(for: Self.stopWindow)
            guard !Task.isCancelled, sending == msg else { return }
            sending = nil
            countdown = nil
            phase = .idle
            deliver(msg)
        }
    }

    private func stopCountdown() {
        guard let msg = sending else { return }
        countdown?.cancel()
        countdown = nil
        sending = nil
        log("stopped the reply to \(msg.to)")
        notes.append("the user STOPPED your reply to \(msg.to) before it went out; nothing was sent")
    }

    // MARK: Hive speaks up

    /// Watches the state; a session that starts waiting for the user gets announced once the voice is free.
    private func poll() async {
        let state = await Task.detached { StateBuilder.build().sessions }.value
        if !inTurn { sessions = state }
        let needs = Attention.needs(state)
        let (added, removed) = tracker.update(needs, now: Date())
        // the tracker stays quiet on its first call; the voice says once who is already waiting
        if !polled { polled = true; for (name, need) in needs { announce[name] = need.reason } }
        for name in removed { announce[name] = nil }
        for (name, why) in added { announce[name] = why }
        announceNext()
    }

    private func announceNext() {
        guard phase == .idle, !inTurn, sending == nil, !announce.isEmpty else { return }
        let names = announce.keys.sorted()
        let lines = names.map { name in
            let said = sessions.first { $0.name == name }?.lastSentence.map { " – its last words: \"\($0)\"" } ?? ""
            return "\(name) needs the user: \(announce[name] ?? "")\(said)"
        }
        announce = [:]
        // with several at once, the first one named is in focus
        focus = names.first
        turn(user: nil, event: lines.joined(separator: "\n") + "\nTell the user in one or two short sentences who needs them "
            + "and what for, so they can answer by voice\(names.count > 1 ? "; name \(names[0]) first" : ""). No markers.")
    }

    private func tick() {
        switch phase {
        case .thinking where speaker.isSpeaking: phase = .speaking
        case .thinking where !inTurn: phase = .idle
        case .speaking where !speaker.isSpeaking && !inTurn: phase = .idle
        case .idle: announceNext()
        default: break
        }
    }
}
