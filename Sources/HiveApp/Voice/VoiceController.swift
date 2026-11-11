import AppKit
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
    /// Quick replies of the last answer, waiting out the pause for "stop"; empty = none
    @Published private(set) var sending: [Handoff.Message] = []
    @Published private(set) var focus: String?
    @Published private(set) var problem: String?
    @Published private(set) var needsInputMonitoring = false
    @Published private(set) var hasElevenKey = false
    /// listening without the key (conversation mode): ends by itself on a pause
    @Published private(set) var handsFree = false
    private var listenStarted = Date()
    private var heardChanged = Date()
    /// since when the voice has been silent, so the microphone doesn't catch the end of its own sentence
    private var quietSince: Date?
    static let echoGap: TimeInterval = 0.4

    /// pause after a quick reply has been read out, in which pressing the key still stops it
    static let stopWindow: Duration = .seconds(2.5)
    /// conversation mode: how long the microphone stays open after an answer if nobody speaks,
    /// and how long a pause ends what was said
    static let followUpWait: TimeInterval = 6
    static let endOfSpeech: TimeInterval = 1.2

    private unowned let store: StateStore
    private let listener = Listener(locale: VoiceSettings.locale)
    private let brain = Brain(name: Brain.voiceName, systemPrompt: Brain.voicePrompt)
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
    /// the microphone opens by itself after an answer only if a reply is expected: Hive asked something,
    /// a message waits for a yes, or it announced a session that waits for the user
    private var expectsReply = false
    private var announcedNeed = false
    private var filter = SpokenFilter()
    private var splitter = SentenceSplitter()
    private var asked = Date()
    private var firstSentence = true
    private var tracker = AttentionTracker()
    private var polled = false
    private var announce: [String: String] = [:]   // session → why it needs the user, not yet told
    private var doneTracker = DoneTracker()
    private var finished: [String: String] = [:]   // session → its task line, finished and not yet told
    private var countdown: Task<Void, Never>?
    private var ticker: Timer?
    private var settings: AnyCancellable?
    private var keyChanged: AnyCancellable?
    private var model = VoiceSettings.model

    init(store: StateStore) {
        self.store = store
        listener.onPartial = { [weak self] text in
            guard let self, text != self.heard else { return }
            self.heard = text
            self.heardChanged = Date()
        }
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
        if phase == .off {
            turnOn()
            if needsInputMonitoring {
                apple.say("Für die rechte Wahltaste braucht Hive die Eingabeüberwachung. Schalt Hive dort in den Systemeinstellungen ein.")
            }
        }
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
        finished = [:]
        polled = false
        tracker = AttentionTracker()
        doneTracker = DoneTracker()
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
        // already listening hands-free: the key takes over, its release ends it
        if phase == .listening { handsFree = false; return }
        startListening(handsFree: false)
    }

    private func startListening(handsFree: Bool) {
        heard = ""
        answer = ""
        self.handsFree = handsFree
        listenStarted = Date()
        heardChanged = Date()
        phase = .listening
        Task {
            do { try await listener.start() } catch {
                problem = error.localizedDescription
                voiceLog("listener: \(problem ?? "")")
                phase = .idle
            }
        }
    }

    private func talkReleased() {
        guard phase == .listening else { return }
        handsFree = false
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
        handsFree = false
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

    /// The pill's close button: stop whatever runs (speaking, listening, a reply about to go out) and go quiet.
    /// An answer still on its way is dropped.
    func dismiss() {
        guard phase != .off else { return }
        stopSpeaking()
        stopCountdown()
        if phase == .listening { Task { _ = await listener.stop() } }
        handsFree = false
        heard = ""
        answer = ""
        quietSince = nil
        phase = .idle
        dismissed = Date()
    }

    /// set by `dismiss()`, so the pill hides at once instead of lingering
    @Published private(set) var dismissed = Date.distantPast

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
            if let me = VoiceSettings.userName {
                prompt += "[HIVE] the user is \(me); call them by name now and then, not in every answer\n"
            }
            if let p = handoff.pending { prompt += "[HIVE] proposal waiting for a yes: to \(p.to): \(p.text)\n" }
            if let focus { prompt += "[HIVE] focus: \(focus) (you announced it last; a reply without a name means this session)\n" }
            if let open = store.selected, open != focus { prompt += "[HIVE] open in the Hive window: \(open)\n" }
            prompt += notes.map { "[HIVE] \($0)\n" }.joined()
            notes = []
            if let event { prompt += "\n[HIVE EVENT] \(event)" }
            if let text { prompt += "\n[USER] \(text)" }
            asked = Date()
            voiceLog(text.map { "you: \($0)" } ?? "event: \((event ?? "").replacingOccurrences(of: "\n", with: " ⏎ "))")
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
            let reachable = Set(store.displaySessions.filter { store.tmux($0) != nil }.map(\.name))
            let actions = handoff.apply(directives, reachable: reachable)
            let now = actions.compactMap { if case let .send(m) = $0 { m } else { nil } }
            let later = actions.compactMap { if case let .countdown(m) = $0 { m } else { nil } }
            if !now.isEmpty { Task { for m in now { await deliver(m) } } }
            if !later.isEmpty { startCountdown(later) }
        } else {
            // the user interrupted: the answer was not heard, so any proposal in it does not count
            notes.append("the user interrupted your last answer; they did not hear it to the end")
        }
        pending = handoff.pending
        let said = Directives.parse(full).spoken
        expectsReply = !discard && (said.hasSuffix("?") || pending != nil || announcedNeed)
        announcedNeed = false
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

    private func session(_ name: String) -> Session? { store.session(named: name) }

    private func deliver(_ msg: Handoff.Message) async {
        let why: String? = switch await store.deliver(msg.text, to: msg.to) {
        case nil: nil
        case .unknownSession: "Eine Session \(msg.to) kenne ich nicht."
        case .notInHive: "\(msg.to) läuft nicht in Hive, dort kann ich nichts eintippen."
        case .dialogChanged: "Bei \(msg.to) hat sich der Dialog geändert, schau bitte selbst."
        case .noMatchingOption: "\(msg.to) zeigt eine Auswahl, da passt \"\(msg.text)\" nicht. Sag mir die Nummer."
        case .typingFailed: "Das Eintippen bei \(msg.to) hat nicht geklappt."
        }
        if let why {
            voiceLog("not sent to \(msg.to): \(why)")
            notes.append("sending to \(msg.to) FAILED: \(why)")
            voice(why)
        } else {
            // no "sent" from the voice: the answer already said where it goes, the pill shows it
            voiceLog("sent to \(msg.to): \(msg.text)")
            notes.append("message delivered to \(msg.to): \(msg.text)")
        }
    }

    // MARK: quick reply with a pause for "stop"

    /// One pause for all of them, then they go out one after the other.
    private func startCountdown(_ msgs: [Handoff.Message]) {
        stopCountdown(silently: true)
        sending = msgs
        countdown = Task {
            while speaker.isSpeaking { try? await Task.sleep(for: .milliseconds(100)) }
            phase = .countdown
            try? await Task.sleep(for: Self.stopWindow)
            guard !Task.isCancelled, sending == msgs else { return }
            sending = []
            countdown = nil
            phase = .idle
            for m in msgs { await deliver(m) }
        }
    }

    private func stopCountdown(silently: Bool = false) {
        guard !sending.isEmpty else { return }
        let to = sending.map(\.to).joined(separator: ", ")
        countdown?.cancel()
        countdown = nil
        sending = []
        if phase == .countdown { phase = .idle }
        guard !silently else { return }
        voiceLog("stopped the reply to \(to)")
        notes.append("the user STOPPED your reply to \(to) before it went out; nothing was sent")
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

        // the session open in front of the user needs no announcement
        let inFront = NSApp.isActive ? store.selected : nil
        for (name, task) in doneTracker.update(store.displaySessions, now: Date()) where name != inFront && announce[name] == nil {
            finished[name] = task
        }
        if !VoiceSettings.announceDone { finished = [:] }
    }

    private func announceNext() {
        guard phase == .idle, !inTurn, sending.isEmpty, !announce.isEmpty || !finished.isEmpty else { return }
        func said(_ name: String) -> String { session(name)?.lastSentence.map { " – its last words: \"\($0)\"" } ?? "" }
        let names = announce.keys.sorted()
        let done = finished.keys.sorted()
        var lines = names.map { "\($0) needs the user: \(announce[$0] ?? "")\(said($0))" }
        lines += done.map { name in
            let task = finished[name].map { $0.isEmpty ? "" : " task \"\($0)\"" } ?? ""
            return "\(name) is done\(task)\(said(name))"
        }
        announce = [:]
        finished = [:]
        // whoever needs the user comes first and is in focus; otherwise the finished one (to give it the next step)
        focus = names.first ?? done.first
        let ask = names.isEmpty
            ? "Tell the user in one short sentence who finished and the gist of the result, no details."
            : "Tell the user in one or two short sentences who needs them and what for, so they can answer by voice;"
              + " say in plain words what the session wants to do (\"will 'n Befehl ausführen\", \"will die Datei ändern\"),"
              + " never a label like \"Berechtigungs-Dialog\" or \"Auswahl\""
              + (names.count > 1 ? "; name \(names[0]) first" : "") + (done.isEmpty ? "" : "; mention the finished ones briefly at the end") + "."
        announcedNeed = !names.isEmpty
        turn(user: nil, event: lines.joined(separator: "\n") + "\n" + ask + " No markers.")
    }

    private var lastWatch = Date.distantPast

    private func tick() {
        if Date().timeIntervalSince(lastWatch) >= 2 { lastWatch = Date(); watchNeeds() }
        switch phase {
        case .thinking where speaker.isSpeaking: phase = .speaking
        case .thinking where !inTurn: phase = .idle
        case .speaking where speaker.isSpeaking || inTurn:
            quietSince = nil
        case .speaking:
            let quiet = quietSince ?? Date()
            quietSince = quiet
            guard Date().timeIntervalSince(quiet) >= Self.echoGap else { break }
            quietSince = nil
            // conversation mode: the user can just answer, no key needed
            if VoiceSettings.followUp, expectsReply, listenerReady, sending.isEmpty { startListening(handsFree: true) } else { phase = .idle }
        case .listening where handsFree:
            let now = Date()
            if heard.isEmpty, now.timeIntervalSince(listenStarted) > Self.followUpWait { talkCancelled() }
            else if !heard.isEmpty, now.timeIntervalSince(heardChanged) > Self.endOfSpeech { talkReleased() }
        case .idle: announceNext()
        default: break
        }
    }
}
