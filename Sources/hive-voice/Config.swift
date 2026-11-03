import Foundation

enum Output: String, CaseIterable {
    case apple, eleven

    var label: String { self == .apple ? "macOS voice" : "ElevenLabs" }
    var toggled: Output { self == .apple ? .eleven : .apple }
}

/// Settings from the command line, e.g. `hive-voice --output eleven --model haiku`.
struct Config {
    var output: Output = .apple
    var model = "haiku"
    var locale = "de-DE"
    var elevenVoice = "JBFqnCBsd6RMkjVDRZzb"        // a premade voice; any voice speaks German with the multilingual models
    var elevenModel = "eleven_flash_v2_5"           // the low-latency model
    /// type instead of talking (stdin), for testing without a microphone
    var textMode = false

    static let usage = """
    hive-voice [--output apple|eleven] [--model haiku|sonnet|…] [--voice-id ID] [--eleven-model ID] [--text]
      hold ⌃⌥Space to talk, ⌃⌥V switches the output, ⌃⌥Q quits
    """

    static func parse(_ args: [String]) -> Config {
        var c = Config()
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--output": if let v = it.next().flatMap(Output.init(rawValue:)) { c.output = v }
            case "--model": if let v = it.next() { c.model = v }
            case "--voice-id": if let v = it.next() { c.elevenVoice = v }
            case "--eleven-model": if let v = it.next() { c.elevenModel = v }
            case "--locale": if let v = it.next() { c.locale = v }
            case "--text": c.textMode = true
            case "-h", "--help": print(usage); exit(0)
            default: break
            }
        }
        return c
    }
}

/// The ElevenLabs key never lives in the repo: Keychain item first, then a file in the home folder.
enum Secrets {
    static let keychainService = "hive-voice-elevenlabs"
    static let keyFile = NSString(string: "~/.config/hive-voice/elevenlabs-key").expandingTildeInPath

    static func elevenLabsKey() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            p.waitUntilExit()
            let key = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if p.terminationStatus == 0, !key.isEmpty { return key }
        }
        let file = (try? String(contentsOfFile: keyFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return file?.isEmpty == false ? file : nil
    }
}

func log(_ s: String) {
    let t = Date().formatted(.dateTime.hour().minute().second())
    FileHandle.standardError.write(Data("[\(t)] \(s)\n".utf8))
}
