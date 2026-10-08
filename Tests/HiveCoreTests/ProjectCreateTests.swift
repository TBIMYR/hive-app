import Testing
@testable import HiveCore

@Test func folderStepCommands() {
    #expect(ProjectCreate.command(.empty, folder: "/d/lumen", hasGh: true) == ["git", "init", "-q", "/d/lumen"])
    #expect(ProjectCreate.command(.clone("acme/lumen"), folder: "/d/lumen", hasGh: true) == ["gh", "repo", "clone", "acme/lumen", "/d/lumen"])
    #expect(ProjectCreate.command(.clone("acme/lumen"), folder: "/d/lumen", hasGh: false)
            == ["git", "clone", "https://github.com/acme/lumen.git", "/d/lumen"])
    #expect(ProjectCreate.command(.clone("git@github.com:acme/lumen.git"), folder: "/d/l", hasGh: false)?[2] == "git@github.com:acme/lumen.git")
    #expect(ProjectCreate.command(.existing, folder: "/d/lumen", hasGh: true) == nil)
}

@Test func repoRefs() {
    #expect(ProjectCreate.isRepoRef("acme/lumen") && ProjectCreate.isRepoRef("https://github.com/acme/lumen"))
    #expect(!ProjectCreate.isRepoRef("lumen") && !ProjectCreate.isRepoRef("a/b/c") && !ProjectCreate.isRepoRef(""))
    #expect(ProjectCreate.cloneURL("acme/lumen.git") == "https://github.com/acme/lumen.git")
}

@Test func validation() {
    let ok = ProjectCreate.Input(slug: "lumen", prefix: "lu", folder: "/d/lumen", source: .empty)
    let none: (String) -> Bool = { _ in false }
    #expect(ProjectCreate.validate(ok, registered: [], takenPrefixes: [], exists: none) == nil)
    #expect(ProjectCreate.validate(ok, registered: [ProjectInfo(slug: "lumen")], takenPrefixes: [], exists: none) != nil)
    #expect(ProjectCreate.validate(ok, registered: [], takenPrefixes: ["lu"], exists: none) != nil)
    #expect(ProjectCreate.validate(ok, registered: [], takenPrefixes: [], exists: { _ in true }) != nil)
    var bad = ok; bad.slug = "Lu.men"
    #expect(ProjectCreate.validate(bad, registered: [], takenPrefixes: [], exists: none) != nil)
    var ex = ok; ex.source = .existing
    #expect(ProjectCreate.validate(ex, registered: [], takenPrefixes: [], exists: none) != nil)
    #expect(ProjectCreate.validate(ex, registered: [], takenPrefixes: [], exists: { _ in true }) == nil)
    #expect(ProjectCreate.validate(ex, registered: [ProjectInfo(slug: "x", folder: "/d/lumen")], takenPrefixes: [], exists: { _ in true }) != nil)
    var cl = ok; cl.source = .clone("nope")
    #expect(ProjectCreate.validate(cl, registered: [], takenPrefixes: [], exists: none) != nil)
}
