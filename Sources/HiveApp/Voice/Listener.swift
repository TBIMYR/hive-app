import AVFoundation
import ObjCTry
import Speech

/// Push to talk with on-device recognition (SpeechAnalyzer + SpeechTranscriber).
/// `start()` on key down, `stop()` on key up returns the final text.
@available(macOS 26, *)
@MainActor
final class Listener {
    private let locale: Locale
    private var engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<String, Never>?
    private var format: AVAudioFormat?
    var onPartial: ((String) -> Void)?
    /// words the recogniser should expect (the spoken session names)
    var vocabulary: [String] = []

    init(locale: String) { self.locale = Locale(identifier: locale) }

    /// Asks for microphone access and downloads the German model if it is missing.
    func prepare() async throws {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure("no microphone access (System Settings → Privacy → Microphone)") }
        guard SpeechTranscriber.isAvailable else { throw Failure("SpeechTranscriber is not available on this Mac") }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw Failure("no speech model for \(locale.identifier)")
        }
        let probe = SpeechTranscriber(locale: supported, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
            voiceLog("downloading the speech model for \(supported.identifier) …")
            try await request.downloadAndInstall()
        }
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
        voiceLog("speech recognition ready (\(supported.identifier))")
    }

    func start() async throws {
        guard let format else { throw Failure("speech recognition is not ready") }
        if analyzer != nil {
            // a stop that never finished (results that never end) must not block every later start
            voiceLog("listener: the last recording was still open, dropping it")
            drop()
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation

        // Microphone first: whatever is said while the analyzer starts is buffered in the stream.
        // A new engine each time: one kept from before still holds the formats of a device that may be gone
        // (headset switched, Bluetooth changed to its call mode), and installTap then throws an ObjC exception.
        engine = AVAudioEngine()
        let mic = engine.inputNode
        let micFormat = mic.inputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else { throw Failure("no microphone input") }
        guard let converter = AVAudioConverter(from: micFormat, to: format) else { throw Failure("audio format not convertible") }
        var startError: Error?
        if let e = HiveTry({
            mic.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
                if let converted = Self.convert(buffer, with: converter, to: format) {
                    continuation.yield(AnalyzerInput(buffer: converted))
                }
            }
            engine.prepare()
            do { try engine.start() } catch { startError = error }
        }) {
            input = nil
            throw Failure("microphone: \(e)")
        }
        if let startError {
            _ = HiveTry { mic.removeTap(onBus: 0) }
            input = nil
            throw startError
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber],
                                      options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        self.transcriber = transcriber
        self.analyzer = analyzer
        collector = Task { [weak self] in
            var final = ""
            do {
                for try await r in transcriber.results {
                    let text = String(r.text.characters)
                    if r.isFinal {
                        final += text
                        await MainActor.run { self?.onPartial?(final) }
                    } else {
                        let shown = final + text
                        await MainActor.run { self?.onPartial?(shown) }
                    }
                }
            } catch { voiceLog("recognition: \(error.localizedDescription)") }
            return final
        }
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try? await analyzer.setContext(context)
        }
        try await analyzer.start(inputSequence: stream)
    }

    func stop() async -> String {
        guard let analyzer else { return "" }
        let collector = self.collector
        // cleared first: a second stop (key up and an event at once) or a start meanwhile finds nothing open
        self.analyzer = nil
        self.collector = nil
        transcriber = nil
        _ = HiveTry {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        input?.finish()
        input = nil
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        // the results can fail to end (analyzer already finished); after a few seconds take what came
        let timeout = Task { try? await Task.sleep(for: .seconds(3)); collector?.cancel() }
        let text = await collector?.value ?? ""
        timeout.cancel()
        if text.isEmpty { voiceLog("listener: heard nothing") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func drop() {
        _ = HiveTry {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        input?.finish()
        collector?.cancel()
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        self.analyzer = nil
        transcriber = nil
        input = nil
        collector = nil
    }

    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}
