import Foundation
import HiveCore

/// Session names as the voice says them: "lu.01" → "Lumen eins", "or.pm" → "Orbit PM".
/// The project name is used when the prefix abbreviates it; otherwise the prefix itself ("helper.02" → "Helper zwei").
/// Own names (`~/.config/hive-voice/names.json`) win, for a whole name or a prefix: {"lu": "Luna", "or.pm": "Chefin"}.
public struct SpokenNames: Equatable, Sendable {
    /// real name → spoken name
    public let spoken: [String: String]

    public init(_ sessions: [Session], overrides: [String: String] = [:]) {
        var m: [String: String] = [:]
        for s in sessions where m[s.name] == nil {
            m[s.name] = overrides[s.name] ?? Self.say(s.name, project: s.project.isEmpty ? s.group : s.project, overrides: overrides)
        }
        // two sessions that would sound the same keep their real names
        let clashes = Dictionary(grouping: m.keys, by: { m[$0]!.lowercased() }).values.filter { $0.count > 1 }.flatMap { $0 }
        for name in clashes where overrides[name] == nil { m[name] = name }
        spoken = m
    }

    static func say(_ name: String, project: String, overrides: [String: String]) -> String {
        let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
        // only "prefix.number" and "prefix.pm" follow the scheme; other names are read with pauses for . and -
        guard parts.count == 2, parts[1].lowercased() == "pm" || Int(parts[1]) != nil else {
            return name.replacingOccurrences(of: #"[.\-_]"#, with: " ", options: .regularExpression)
        }
        let prefix = parts[0], suffix = parts[1]
        let word: String
        if let own = overrides[prefix] { word = own }
        else if !project.isEmpty, project.lowercased().hasPrefix(prefix.lowercased()) { word = project.capitalized }
        else { word = prefix.capitalized }
        return "\(word) \(Int(suffix).map(Self.number) ?? "PM")"
    }

    static let numbers = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn",
                          "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn", "zwanzig"]

    static func number(_ n: Int) -> String { n >= 0 && n < numbers.count ? numbers[n] : String(n) }

    /// Replaces every session name in a sentence that goes to the voice (also "Lu.01" at the start of a sentence).
    public func speakable(_ sentence: String) -> String {
        var out = sentence
        for name in spoken.keys.sorted(by: { $0.count > $1.count }) where spoken[name] != name {
            let pattern = "(?<![\\w.])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\w]|\\.\\w)"
            out = out.replacingOccurrences(of: pattern, with: NSRegularExpression.escapedTemplate(for: spoken[name]!),
                                           options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    public static func loadOverrides(_ path: String = NSString(string: "~/.config/hive-voice/names.json").expandingTildeInPath) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let m = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return m
    }
}
