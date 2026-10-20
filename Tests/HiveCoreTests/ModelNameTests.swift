import Testing
@testable import HiveCore

@Test func shortModelNames() {
    #expect(ModelName.short("claude-opus-5-5") == "Opus 5.5")
    #expect(ModelName.short("claude-fable-5-1") == "Fable 5.1")
    #expect(ModelName.short("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
    #expect(ModelName.short("claude-haiku-5-5[1m]") == "Haiku 5.5")
    #expect(ModelName.short("claude-opus-4-20250514") == "Opus 4")
    #expect(ModelName.short("claude-3-5-sonnet-20241022") == "Sonnet 3.5")
}

@Test func unknownModelNamesStayAsTheyAre() {
    #expect(ModelName.short("gpt-x") == "gpt-x")
    #expect(ModelName.short("") == "")
}
