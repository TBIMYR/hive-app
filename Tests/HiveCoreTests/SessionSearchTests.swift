import Testing
@testable import HiveCore

@Test func emptyQueryMatchesEverything() {
    #expect(SessionSearch.matches("", in: ["lu.01"]))
    #expect(SessionSearch.matches("   ", in: []))
}

@Test func everyWordMustAppearSomewhere() {
    let fields = ["or.02", "orbit", "Android build", "waiting for the store review"]
    #expect(SessionSearch.matches("android", in: fields))
    #expect(SessionSearch.matches("orbit review", in: fields))
    #expect(!SessionSearch.matches("orbit ios", in: fields))
}

@Test func ignoresCaseAndAccents() {
    #expect(SessionSearch.matches("CAFE", in: ["Café menu"]))
    #expect(SessionSearch.matches("überblick", in: ["Ueberblick", "Überblick"]))
    #expect(SessionSearch.matches("fj.0", in: ["FJ.03"]))
}

@Test func nilAndEmptyFieldsAreSkipped() {
    #expect(SessionSearch.matches("kiosk", in: [nil, "", "kiosk"]))
    #expect(!SessionSearch.matches("kiosk", in: [nil, ""]))
}
