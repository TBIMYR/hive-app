import AVFoundation
import Speech

/// Push to talk with on-device recognition (SpeechAnalyzer + SpeechTranscriber).
/// `start()` on key down, `stop()` on key up returns the final text.
@available(macOS 26, *)
@MainActor
final class Listener {
    private let locale: Locale
    private let engine = AVAudioEngine()
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
            log("downloading the speech model for \(supported.identifier) …")
            try await request.downloadAndInstall()
        }
        format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [probe])
        log("speech recognition ready (\(supported.identifier))")
    }

    func start() async throws {
        guard analyzer == nil, let format else { return }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        input = continuation

        // Microphone first: whatever is said while the analyzer starts is buffered in the stream
        let mic = engine.inputNode
        let micFormat = mic.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: format) else { throw Failure("audio format not convertible") }
        mic.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { buffer, _ in
            if let converted = Self.convert(buffer, with: converter, to: format) {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        engine.prepare()
        try engine.start()

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
            } catch { log("recognition: \(error.localizedDescription)") }
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        input?.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        let text = await collector?.value ?? ""
        self.analyzer = nil
        transcriber = nil
        input = nil
        collector = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
