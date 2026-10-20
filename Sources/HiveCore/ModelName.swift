import Foundation

/// Model IDs from the transcript ("claude-opus-5-5", "claude-sonnet-4-5-20250929") as short names for the cards.
public enum ModelName {
    static let families = ["opus", "sonnet", "haiku", "fable"]

    /// "Opus 5.5"; unknown IDs come back unchanged
    public static func short(_ id: String) -> String {
        let base = id.split(separator: "[").first.map(String.init) ?? id
        let parts = base.lowercased().split(separator: "-").map(String.init)
        guard parts.first == "claude", let fam = parts.firstIndex(where: families.contains) else { return id }
        // version: the short numbers around the family name, without the date (8 digits)
        let numbers = parts.dropFirst().filter { $0.count <= 2 && Int($0) != nil }
        guard !numbers.isEmpty else { return parts[fam].capitalized }
        return "\(parts[fam].capitalized) \(numbers.joined(separator: "."))"
    }
}
