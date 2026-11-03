import Combine
import Foundation
import HiveCore
import VoiceKit

/// Talking to Hive: push to talk → on-device recognition → Claude (knows every session) → voice.
/// Hive also speaks up by itself when a session starts waiting for the user; that session is then in focus,
/// so a plain "ja" answers it. Messages to a session only go out after a spoken yes, or, for a short reply to a
/// waiting session, after a pause in which pressing the key stops it. Sending uses the same paths as the
/// reply field and the answer buttons of a card.
@available(macOS 26, *)
@MainActor
final class VoiceController: ObservableObject {
    enum Phase: String {
        case off = "Off", idle = "Ready", listening = "Listening", thinking = "Thinking", speaking = "Speaking"
        case countdown = "Sending"
    }

    @Published private(set) var phase = Phase.off { didSet { if phase != oldValue { voiceLog("· \(phase.rawValue)") } } }
    @Published private(set) var heard = ""
    @Published private(set) var answer = ""
    @Published private(set) var pending: Handoff.Message?
    @Published private(set) var sending: Handoff.Message?
    @Published private(set) var focus: String?
    @Published private(set) var problem: String?
    @Published private(set) var needsInputMonitoring = false
    @Published private(set) var hasElevenKey = false

    /// pause after a quick reply has been read out, in which pressing the key still stops it
    static let stopWindow: Duration = .seconds(2.5)

    private unowned let store: StateStore
    private let listener = Listener(locale: VoiceSettings.locale)
    private let brain = Brain()
    private let apple = AppleSpeaker(locale: VoiceSettings.locale)
    private let eleven = ElevenSpeaker()
    private let key = PushToTalk()
    private var listenerReady = false
    private var handoff = Handoff()
    private var notes: [String] = []         // app events for the next turn ("[HIVE] sent to …")
    private var names = SpokenNames([])
    private var discard = false              // barge-in during an answer: drop the rest of it
    private var queued: String?
    private var inTurn = false
    private var filter = SpokenFilter()
    private var splitter = SentenceSplitter()
    private var asked = Date()
    private var firstSentence = true
    private var tracker = AttentionTracker()
    private var polled = false
    private var announce: [String: String] = [:]   // session → why it needs the user, not yet told
    private var countdown: Task<Void, Never>?
    private var ticker: Timer?
    private var settings: AnyCancellable?
    private var keyChanged: AnyCancellable?
    private var model = VoiceSettings.model

    init(store: StateStore) {
        self.store = store
        listener.onPartial = { [weak self] in self?.heard = $0 }
        eleven.onError = { [weak self] msg in self?.apple.say(msg) }
        key.onPress = { [weak self] in self?.talkPressed() }
        key.onRelease = { [weak self] in self?.talkReleased() }
        key.onCancel = { [weak self] in self?.talkCancelled() }
        key.onPermission = { [weak self] in self?.needsInputMonitoring = $0 }
        settings = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
        keyChanged = NotificationCenter.default.publisher(for: .voiceKeyChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadKey() }
        applySettings()
    }

    private var speaker: Speaker { VoiceSettings.output == .eleven && eleven.key != nil ? eleven : apple }

    /// Turns everything on or off with the switch, and follows the trigger key setting.
    private func applySettings() {
        guard VoiceSettings.enabled else {
            if phase != .off { turnOff() }
            return
        }
        key.start(VoiceSettings.trigger)
        if phase == .off { turnOn() }
        // the next question starts Claude with the new model (and a new conversation)
        if VoiceSettings.model != model { model = VoiceSettings.model; brain.stop() }
    }

    private func turnOn() {
        phase = .idle
        problem = nil
        reloadKey()
        brain.start()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        Task {
            do {
                try await listener.prepare()
                listenerReady = true
            } catch {
                problem = error.localizedDescription
                voiceLog("speech recognition: \(error.localizedDescription)")
            }
        }
    }

    private func turnOff() {
        key.stop()
        stopSpeaking()
        stopCountdown(silently: true)
        if phase == .listening { Task { _ = await listener.stop() } }
        brain.stop()
        ticker?.invalidate()
        ticker = nil
        phase = .off
        heard = ""
        answer = ""
        focus = nil
        announce = [:]
        polled = false
        tracker = AttentionTracker()
    }

    private func reloadKey() {
        eleven.reloadKey()
        hasElevenKey = eleven.key != nil
    }

    // MARK: push to talk

    private func talkPressed() {
        guard phase != .off else { return }
        stopSpeaking()
        stopCountdown()
        guard listenerReady else {
            apple.say(problem ?? "Die Spracherkennung lädt noch.")
            return
        }
        heard = ""
        answer = ""
        phase = .listening
        Task {
            do { try await listener.start() } catch {
                problem = error.localizedDescription
                phase = .idle
            }
        }
    }

    private func talkReleased() {
        guard phase == .listening else { return }
        Task {
            let text = await listener.stop()
            heard = text
            if text.isEmpty { phase = .idle; return }
            turn(user: text)
        }
    }

    /// Right ⌥ was part of a key combination (e.g. ⌥L for @): throw the recording away.
    private func talkCancelled() {
        guard phase == .listening else { return }
        Task {
            _ = await listener.stop()
            heard = ""
            phase = .idle
        }
    }

    /// Barge-in: silence at once, and whatever Claude still sends for this answer is dropped.
    private func stopSpeaking() {
        apple.stop()
        eleven.stop()
        if brain.isBusy { discard = true }
    }

    // MARK: one turn

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
            let sessions = store.displaySessions
            names = SpokenNames(sessions, overrides: SpokenNames.loadOverrides())
            listener.vocabulary = Array(names.spoken.values)
            var prompt = "[HIVE STATE \(Date().formatted(date: .omitted, time: .shortened))]\n\(StateSummary.lines(sessions, names: names))\n"
            // the choices a waiting session shows, so "ja" can become the right option
            for name in store.needs.keys.sorted() {
                guard let s = session(name), let dialog = await store.dialog(s) else { continue }
                prompt += "[HIVE] \(name) shows a choice dialog: \(DialogReply.describe(dialog))\n"
            }
            if let p = handoff.pending { prompt += "[HIVE] proposal waiting for a yes: to \(p.to): \(p.text)\n" }
            if let focus { prompt += "[HIVE] focus: \(focus) (you announced it last; a reply without a name means this session)\n" }
            if let open = store.selected, open != focus { prompt += "[HIVE] open in the Hive window: \(open)\n" }
            prompt += notes.map { "[HIVE] \($0)\n" }.joined()
            notes = []
            if let event { prompt += "\n[HIVE EVENT] \(event)" }
            if let text { prompt += "\n[USER] \(text)" }
            asked = Date()
            voiceLog(text.map { "you: \($0)" } ?? "event")
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
            voiceLog("claude: \(full.replacingOccurrences(of: "\n", with: " ⏎ "))")
            switch handoff.apply(directives, waiting: Set(store.needs.keys)) {
            case let .send(msg): Task { await deliver(msg) }
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
        if let next = queued { queued = nil; turn(user: next) }
    }

    private func speak(_ sentences: [String]) {
        for s in sentences {
            if firstSentence {
                firstSentence = false
                voiceLog(String(format: "first sentence after %.2fs", Date().timeIntervalSince(asked)))
            }
            voice(s)
        }
    }

    /// Everything the voice says goes through here, so session names are spoken as words.
    private func voice(_ text: String) { speaker.say(names.speakable(text)) }

    private func session(_ name: String) -> Session? {
        store.displaySessions.first { $0.name == name && ($0.alive || store.tmux($0) != nil) }
            ?? store.displaySessions.first { $0.name == name }
    }

    /// Like a card: a visible choice dialog gets the option (answer buttons), otherwise the text is typed (reply field).
    private func deliver(_ msg: Handoff.Message) async {
        var why: String?
        if let s = session(msg.to) {
            if store.tmux(s) == nil {
                why = "\(msg.to) läuft nicht in Hive, dort kann ich nichts eintippen."
            } else if let dialog = await store.dialog(s) {
                if let a = DialogReply.answer(msg.text, in: dialog) {
                    why = await store.answer(a, known: dialog.options.map(\.label), to: s).map { _ in
                        "Bei \(msg.to) hat sich der Dialog geändert, schau bitte selbst."
                    }
                } else {
                    why = "\(msg.to) zeigt eine Auswahl, da passt \"\(msg.text)\" nicht. Sag mir die Nummer."
                }
            } else {
                why = await store.reply(msg.text, to: s).map { _ in "Das Eintippen bei \(msg.to) hat nicht geklappt." }
            }
        } else {
            why = "Eine Session \(msg.to) kenne ich nicht."
        }
        if let why {
            voiceLog("not sent to \(msg.to): \(why)")
            notes.append("sending to \(msg.to) FAILED: \(why)")
            voice(why)
        } else {
            voiceLog("sent to \(msg.to): \(msg.text)")
            notes.append("message delivered to \(msg.to): \(msg.text)")
            voice("Ist an \(msg.to) raus.")
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
            await deliver(msg)
        }
    }

    private func stopCountdown(silently: Bool = false) {
        guard let msg = sending else { return }
        countdown?.cancel()
        countdown = nil
        sending = nil
        if phase == .countdown { phase = .idle }
        guard !silently else { return }
        voiceLog("stopped the reply to \(msg.to)")
        notes.append("the user STOPPED your reply to \(msg.to) before it went out; nothing was sent")
    }

    // MARK: Hive speaks up

    /// A session that starts waiting for the user gets announced once the voice is free.
    private func watchNeeds() {
        let needs = store.needs
        let (added, removed) = tracker.update(needs, now: Date())
        // the tracker stays quiet on its first call; the voice says once who is already waiting
        if !polled { polled = true; for (name, need) in needs { announce[name] = need.reason } }
        for name in removed { announce[name] = nil }
        for (name, why) in added { announce[name] = why }
        if !VoiceSettings.announce { announce = [:] }
    }

    private func announceNext() {
        guard phase == .idle, !inTurn, sending == nil, !announce.isEmpty else { return }
        let names = announce.keys.sorted()
        let lines = names.map { name in
            let said = session(name)?.lastSentence.map { " – its last words: \"\($0)\"" } ?? ""
            return "\(name) needs the user: \(announce[name] ?? "")\(said)"
        }
        announce = [:]
        // with several at once, the first one named is in focus
        focus = names.first
        turn(user: nil, event: lines.joined(separator: "\n") + "\nTell the user in one or two short sentences who needs them "
            + "and what for, so they can answer by voice\(names.count > 1 ? "; name \(names[0]) first" : ""). No markers.")
    }

    private var lastWatch = Date.distantPast

    private func tick() {
        if Date().timeIntervalSince(lastWatch) >= 2 { lastWatch = Date(); watchNeeds() }
        switch phase {
        case .thinking where speaker.isSpeaking: phase = .speaking
        case .thinking where !inTurn: phase = .idle
        case .speaking where !speaker.isSpeaking && !inTurn: phase = .idle
        case .idle: announceNext()
        default: break
        }
    }
}
