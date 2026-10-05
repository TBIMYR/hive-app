import Foundation
import Testing
@testable import HiveCore

@Test func pricingPicksLongestPrefix() {
    #expect(ModelPricing.of("claude-opus-5-5")?.input == 4)
    #expect(ModelPricing.of("claude-opus-5")?.input == 5)
    #expect(ModelPricing.of("claude-haiku-4-5-20251001")?.output == 5)
    #expect(ModelPricing.of("claude-fable-5-1")?.cacheRead == 0.25)
    #expect(ModelPricing.of("<synthetic>") == nil)
    #expect(ModelPricing.of(nil) == nil)
}

@Test func usdCountsEachTokenKindAtItsRate() throws {
    // Opus 5: 1M each of input, output, cache read, 1h write and 5m write
    let t = TokenCounts(input: 1_000_000, output: 1_000_000, cacheCreation: 2_000_000, cacheCreation1h: 1_000_000,
                        cacheRead: 1_000_000)
    let usd = try #require(ModelPricing.usd(model: "claude-opus-5", t))
    #expect(abs(usd - (5 + 25 + 0.5 + 10 + 6.25)) < 0.0001)
    #expect(ModelPricing.usd(model: "<synthetic>", t) == nil)
}

@Test func lineParserReadsOneHourCacheWrites() throws {
    let text = #"{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":1,"cache_creation_input_tokens":30,"#
        + #""cache_creation":{"ephemeral_5m_input_tokens":10,"ephemeral_1h_input_tokens":20},"output_tokens":2}}}"#
    let line = try #require(UsageScanner.Line.parse(text))
    #expect(line.usage?.cacheCreation1h == 20)
    #expect(line.usage?.cacheCreation == 30)
}
