import Foundation

/// API list prices per million tokens (Anthropic first party, as of 2026-10), to show what the tokens
/// of a subscription would cost via the API. Cache writes: 1-hour TTL 2× input (Claude Code's default),
/// 5-minute TTL 1.25×. Cache reads per model (mostly 0.1× input).
public struct ModelPricing: Equatable, Sendable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double

    /// Longest prefix wins ("claude-opus-5-5" before "claude-opus-5"); dated ids like
    /// "claude-haiku-4-5-20251001" match their family.
    static let table: [(prefix: String, price: ModelPricing)] = [
        ("claude-fable-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", .init(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", .init(input: 10, output: 50, cacheRead: 1)),
        ("claude-mythos-5", .init(input: 10, output: 50, cacheRead: 1)),
        ("claude-opus-5-5", .init(input: 4, output: 20, cacheRead: 0.2)),
        ("claude-opus-5", .init(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-opus-4", .init(input: 5, output: 25, cacheRead: 0.5)),
        ("claude-sonnet-5", .init(input: 2, output: 10, cacheRead: 0.2)),
        ("claude-sonnet-4", .init(input: 3, output: 15, cacheRead: 0.3)),
        ("claude-haiku-4-5", .init(input: 1, output: 5, cacheRead: 0.1)),
    ]

    public static func of(_ model: String?) -> ModelPricing? {
        guard let model else { return nil }
        return table.filter { model.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.price
    }

    /// Dollars for one response; nil for unknown models (e.g. "<synthetic>").
    public static func usd(model: String?, _ t: TokenCounts) -> Double? {
        guard let p = of(model) else { return nil }
        let oneHour = min(t.cacheCreation1h, t.cacheCreation)
        let fiveMin = t.cacheCreation - oneHour
        let perToken = Double(t.input) * p.input + Double(t.output) * p.output + Double(t.cacheRead) * p.cacheRead
            + Double(oneHour) * p.input * 2 + Double(fiveMin) * p.input * 1.25
        return perToken / 1_000_000
    }
}
