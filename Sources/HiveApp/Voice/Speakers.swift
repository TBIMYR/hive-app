import AVFoundation

/// Gets an answer sentence by sentence while it streams in; `stop()` is the barge-in.
@MainActor
protocol Speaker: AnyObject {
    var name: String { get }
    var isSpeaking: Bool { get }
    func say(_ sentence: String)
    func stop()
}

/// Variant 1: macOS voice, the best installed German voice (Premium > Enhanced > Standard).
@MainActor
final class AppleSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var queued = 0
    let name: String

    init(locale: String) {
        let lang = String(locale.prefix(2))
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang) }
        voice = voices.max { a, b in
            (a.quality.rawValue, a.language == locale ? 1 : 0) < (b.quality.rawValue, b.language == locale ? 1 : 0)
        }
        let quality = [AVSpeechSynthesisVoiceQuality.premium: "Premium", .enhanced: "Enhanced"][voice?.quality ?? .default] ?? "Standard"
        name = voice.map { "\($0.name) (\(quality))" } ?? "system voice"
        super.init()
        synth.delegate = self
        if voice?.quality != .premium {
            voiceLog("tip: a Premium German voice sounds much better – System Settings → Accessibility → Spoken Content → System voice → Manage Voices → German")
        }
    }

    var isSpeaking: Bool { queued > 0 }

    func say(_ sentence: String) {
        let u = AVSpeechUtterance(string: sentence)
        u.voice = voice
        u.rate = Float(0.5 * VoiceSettings.speed)
        u.postUtteranceDelay = 0.05
        queued += 1
        synth.speak(u)
    }

    func stop() {
        queued = 0
        synth.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.queued = max(0, self.queued - 1) }
    }
}

/// Variant 2: ElevenLabs streaming TTS. Every sentence goes out as its own request at once (so the next one
/// is already loading while the first plays); the audio streams as raw PCM and is played in order.
@MainActor
final class ElevenSpeaker: Speaker {
    /// read again for every sentence, so a change in Settings counts right away
    var voiceID = VoiceSettings.elevenVoice
    var model = VoiceSettings.elevenModel
    private(set) var key: String?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var chain: Task<Void, Never>?
    private var generation = 0
    private var scheduled = 0
    private var loading = 0
    private var previous = ""
    let name: String
    var onError: ((String) -> Void)?

    /// the key is read on `reloadKey()` (when voice turns on), so the keychain asks only then
    init() {
        name = "ElevenLabs"
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// after the key was saved or removed in Settings
    func reloadKey() { key = VoiceKeychain.read() }

    var hasKey: Bool { key != nil }
    /// last chunk received or buffer played; the player can stall (e.g. when the audio device changes) and
    /// never report its buffers done, so after `stallAfter` without progress it counts as silent
    private var progress = Date()
    static let stallAfter: TimeInterval = 8
    var isSpeaking: Bool {
        guard scheduled > 0 || loading > 0 else { return false }
        if Date().timeIntervalSince(progress) < Self.stallAfter { return true }
        voiceLog("ElevenLabs stalled, stopping")
        stop()
        return false
    }

    func say(_ sentence: String) {
        guard let key else { onError?("ElevenLabs-Schlüssel fehlt."); return }
        if !engine.isRunning { try? engine.start() }
        let gen = generation
        let started = Date()
        let audio = Self.stream(text: sentence, previous: previous, voice: VoiceSettings.elevenVoice, model: model, key: key)
        previous = sentence
        let before = chain
        if !isSpeaking { progress = Date() }
        loading += 1
        chain = Task { [weak self] in
            await before?.value                      // keep the order of the sentences
            var first = true
            do {
                for try await chunk in audio {
                    guard let self, gen == self.generation else { return }
                    if first { first = false; voiceLog(String(format: "ElevenLabs first audio after %.2fs", Date().timeIntervalSince(started))) }
                    self.play(chunk, gen: gen)
                }
            } catch is CancellationError {
            } catch {
                voiceLog("ElevenLabs: \(error.localizedDescription)")
                self?.onError?((error as? Failure)?.message.contains("HTTP 401") == true
                               ? "Der ElevenLabs-Schlüssel stimmt nicht." : "ElevenLabs antwortet nicht.")
            }
            if let self, gen == self.generation { self.loading -= 1 }
        }
    }

    func stop() {
        generation += 1
        chain?.cancel()
        chain = nil
        previous = ""
        player.stop()
        scheduled = 0
        loading = 0
    }

    private func play(_ pcm: Data, gen: Int) {
        let frames = pcm.count / 2
        guard frames > 0, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        let out = buf.floatChannelData![0]
        pcm.withUnsafeBytes { raw in
            let s = raw.bindMemory(to: Int16.self)
            for i in 0..<frames { out[i] = Float(Int16(littleEndian: s[i])) / 32768 }
        }
        scheduled += 1
        progress = Date()
        player.scheduleBuffer(buf) { [weak self] in
            Task { @MainActor in
                guard let self, gen == self.generation else { return }
                self.scheduled = max(0, self.scheduled - 1)
                self.progress = Date()
            }
        }
        if !player.isPlaying { player.play() }
    }

    /// Raw 16-bit PCM at 24 kHz in chunks of about 100 ms.
    nonisolated static func stream(text: String, previous: String, voice: String, model: String, key: String) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { cont in
            let task = Task {
                var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice)/stream?output_format=pcm_24000&optimize_streaming_latency=2")!)
                req.httpMethod = "POST"
                req.setValue(key, forHTTPHeaderField: "xi-api-key")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                var body: [String: Any] = ["text": text, "model_id": model, "language_code": "de",
                                           // less stability = livelier, less like reading the news
                                           "voice_settings": ["stability": VoiceSettings.stability, "similarity_boost": 0.75,
                                                              "style": 0.35, "use_speaker_boost": true, "speed": VoiceSettings.speed]]
                if !previous.isEmpty { body["previous_text"] = previous }
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                        var msg = Data()
                        for try await b in bytes { msg.append(b) }
                        throw Failure("HTTP \(http.statusCode): \(String(decoding: msg.prefix(300), as: UTF8.self))")
                    }
                    var chunk = Data()
                    chunk.reserveCapacity(4800)
                    for try await b in bytes {
                        chunk.append(b)
                        if chunk.count >= 4800 { cont.yield(chunk); chunk = Data() }
                    }
                    if chunk.count > 1 { cont.yield(chunk.prefix(chunk.count & ~1)) }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
