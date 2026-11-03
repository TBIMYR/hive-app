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

    /// premade "Sarah"; with a paid ElevenLabs plan any library voice works too
    static let defaultVoice = "EXAVITQu4vr4xnSDxMaL"
    /// the low-latency model, speaks German
    static let elevenModel = "eleven_flash_v2_5"
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
    static var stability: Double { d.object(forKey: stabilityKey) as? Double ?? 0.3 }

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
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
