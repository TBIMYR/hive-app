import Testing
@testable import HiveCore

@Test func projektAusErstemOrdnerUnterDevelopment() {
    #expect(Project.fromCwd("\(dev)/gamma/gamma-app", devRoot: dev) == "gamma")
    #expect(Project.fromCwd("\(dev)/alpha/worktrees/foo", devRoot: dev) == "alpha")
    #expect(Project.fromCwd("\(dev)/delta", devRoot: dev) == "delta")
}

@Test func projektAusserhalbDevelopmentIstLetzterPfadteil() {
    #expect(Project.fromCwd("/Users/dev", devRoot: dev) == "dev")
    #expect(Project.fromCwd("", devRoot: dev) == "")
}

@Test func gruppeIstPraefixVorDemPunktSonstProjekt() {
    #expect(Project.groupKey("al.pm", project: "alpha") == "al")
    #expect(Project.groupKey("ga.02", project: "gamma") == "ga")
    #expect(Project.groupKey("delta-01", project: "delta") == "delta")
}

@Test func pmErkennung() {
    #expect(Project.isPm("al.pm"))
    #expect(!Project.isPm("al.01"))
    #expect(!Project.isPm("lumen-web-d3"))
}

@Test func slugErsetztAllesAusserAlphanumerisch() {
    #expect(Project.slug("\(dev)/gamma/gamma-app") == "-Users-dev-Development-gamma-gamma-app")
    #expect(Project.slug("/a b/c.d@e") == "-a-b-c-d-e")
    // wie JS je UTF-16-Einheit: ü ist eine Einheit, 🐝 sind zwei
    #expect(Project.slug("/ü🐝") == "----")
}
