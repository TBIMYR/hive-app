import Foundation
import Security

/// Voice settings (Settings → Voice), stored in UserDefaults.
enum VoiceSettings {
    static let enabledKey = "voiceEnabled"
    static let triggerKey = "voiceTrigger"
    static let announceKey = "voiceAnnounce"
    static let outputKey = "voiceOutput"
    static let elevenVoiceKey = "voiceElevenVoice"
    static let modelKey = "voiceModel"
    static let stabilityKey = "voiceStability"
    static let followUpKey = "voiceFollowUp"
    static let announceDoneKey = "voiceAnnounceDone"
    static let userNameKey = "voiceUserName"
    static let speedKey = "voiceSpeed"

    /// premade "Sarah"; with a paid ElevenLabs plan any library voice works too
    static let defaultVoice = "EXAVITQu4vr4xnSDxMaL"
    /// clearer German than the faster flash model, which swallowed words; twice the credits per character
    static let elevenModel = "eleven_multilingual_v2"
    static let locale = "de-DE"

    private static var d: UserDefaults { .standard }
    static var enabled: Bool { d.bool(forKey: enabledKey) }
    static var trigger: Trigger { d.string(forKey: triggerKey).flatMap(Trigger.init) ?? .rightOption }
    static var announce: Bool { d.object(forKey: announceKey) as? Bool ?? true }
    static var announceDone: Bool { d.object(forKey: announceDoneKey) as? Bool ?? true }
    static var output: Output { d.string(forKey: outputKey).flatMap(Output.init) ?? .eleven }
    static var elevenVoice: String {
        let v = d.string(forKey: elevenVoiceKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return v.isEmpty ? defaultVoice : v
    }
    static var model: String { d.string(forKey: modelKey) ?? "haiku" }
    /// after an answer the microphone stays open briefly, so the user can just answer
    static var followUp: Bool { d.object(forKey: followUpKey) as? Bool ?? true }
    static var stability: Double { d.object(forKey: stabilityKey) as? Double ?? 0.5 }
    /// 1 = the voice's normal pace; ElevenLabs takes 0.7 to 1.2
    static var speed: Double { d.object(forKey: speedKey) as? Double ?? 0.92 }
    /// how Hive calls the user; lives only in this Mac's settings, never in the prompt source
    static var userName: String? {
        let n = d.string(forKey: userNameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? nil : n
    }

    enum Trigger: String, CaseIterable {
        case rightOption, controlOptionSpace

        var label: String { self == .rightOption ? "Right ⌥ (hold)" : "⌃⌥Space (hold)" }
        var hint: String { self == .rightOption ? "Hold right ⌥" : "Hold ⌃⌥Space" }
    }

    enum Output: String, CaseIterable {
        case eleven, apple

        var label: String { self == .apple ? "macOS voice" : "ElevenLabs" }
    }
}

/// The ElevenLabs key lives in the login keychain (never in the repo or in UserDefaults).
enum VoiceKeychain {
    static let service = "hive-voice-elevenlabs"
    static let account = "elevenlabs"
    /// older place from the prototype, still read
    static let keyFile = NSString(string: "~/.config/hive-voice/elevenlabs-key").expandingTildeInPath

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
            let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        let file = (try? String(contentsOfFile: keyFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return file?.isEmpty == false ? file : nil
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        q[kSecAttrLabel as String] = "Hive Voice – ElevenLabs"
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove() { SecItemDelete(query as CFDictionary) }
}

func voiceLog(_ s: String) {
    FileHandle.standardError.write(Data("hive voice: \(s)\n".utf8))
    VoiceLogFile.append(s)
}

/// What the voice and the broadcast field heard, said and did, in ~/Library/Logs/Hive/voice.log, so a wrong
/// answer can be looked up afterwards (stderr goes nowhere in the installed app). Over `limit` the file moves to
/// voice.log.1 and a new one starts, so at most twice that stays on disk.
enum VoiceLogFile {
    static let limit = 2_000_000
    static let path = NSString(string: "~/Library/Logs/Hive/voice.log").expandingTildeInPath
    private static let queue = DispatchQueue(label: "hive.voicelog")
    nonisolated(unsafe) private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func append(_ s: String) {
        let now = Date()
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int, size > limit {
                try? fm.removeItem(atPath: path + ".1")
                try? fm.moveItem(atPath: path, toPath: path + ".1")
            }
            let line = Data("\(stamp.string(from: now)) \(s)\n".utf8)
            if let h = FileHandle(forWritingAtPath: path) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: line)
            } else {
                fm.createFile(atPath: path, contents: line)
            }
        }
    }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
