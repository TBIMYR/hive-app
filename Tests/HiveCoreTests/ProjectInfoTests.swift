import Foundation
import Testing
@testable import HiveCore

private let h = "/Users/dev"

@Test func parsesFrontmatterAndBody() {
    let text = "---\nfolder: ~/Development/lumen\nprefix: lu\nowner: Mika\n---\n## Links\n- x\n"
    let p = ProjectInfo.parse(text, slug: "lumen", home: h)
    #expect(p.folder == "/Users/dev/Development/lumen")
    #expect(p.prefix == "lu")
    #expect(p.extra == ["owner: Mika"])
    #expect(p.body == "## Links\n- x\n")
    #expect(p.render(home: h) == text)
}

@Test func withoutFrontmatterTheWholeTextIsBody() {
    let p = ProjectInfo.parse("just notes\n", slug: "orbit", home: h)
    #expect(p.folder == nil && p.prefix == nil && p.body == "just notes\n")
    #expect(p.render(home: h) == "just notes\n")
}

@Test func templateHasSectionsAndTildeFolder() {
    let p = ProjectInfo.template(slug: "fjord", folder: "/Users/dev/Development/fjord", prefix: "fj")
    #expect(p.render(home: h) == "---\nfolder: ~/Development/fjord\nprefix: fj\n---\n## Links\n\n## Test accounts\n\n## Notes\n")
}

@Test func slugRules() {
    #expect(ProjectInfo.isValidSlug("lumen") && ProjectInfo.isValidSlug("a1_b-c"))
    #expect(!ProjectInfo.isValidSlug("") && !ProjectInfo.isValidSlug(".x") && !ProjectInfo.isValidSlug("a.b")
            && !ProjectInfo.isValidSlug("..") && !ProjectInfo.isValidSlug("Lumen") && !ProjectInfo.isValidSlug("-a"))
    #expect(ProjectInfo.slug(from: "My Kiosk.app") == "my-kiosk-app")
    #expect(ProjectInfo.slug(from: "__x__") == "x")
    #expect(ProjectInfo.slug(from: "...") == nil)
}

private let lumen = ProjectInfo(slug: "lumen", folder: "/Users/dev/Development/lumen", prefix: "lu")
private let inner = ProjectInfo(slug: "lumen-web", folder: "/Users/dev/Development/lumen/web", prefix: "lw")
private let loose = ProjectInfo(slug: "orbit")   // file without folder

@Test func matchesExactParentAndNested() {
    let all = [lumen, inner, loose]
    #expect(ProjectInfo.match(cwd: "/Users/dev/Development/lumen", in: all)?.slug == "lumen")
    #expect(ProjectInfo.match(cwd: "/Users/dev/Development/lumen/src", in: all)?.slug == "lumen")
    #expect(ProjectInfo.match(cwd: "/Users/dev/Development/lumen/web/app", in: all)?.slug == "lumen-web")
    #expect(ProjectInfo.match(cwd: "/Users/dev/Development/lumenx", in: all) == nil)
}

@Test func matchesTildeFolderFromFile() {
    let p = ProjectInfo.parse("---\nfolder: ~/Development/kiosk/\n---\n", slug: "kiosk", home: h)
    #expect(ProjectInfo.match(cwd: "/Users/dev/Development/kiosk/a", in: [p])?.slug == "kiosk")
}

@Test func resolveFallsBackToFolderName() {
    let all = [lumen, loose]
    #expect(ProjectInfo.resolve(cwd: "/Users/dev/Development/orbit/x", in: all, devRoot: dev)?.slug == "orbit")
    #expect(ProjectInfo.resolve(cwd: "/Users/dev/Development/orbit/x", in: all, devRoot: dev)?.info == loose)
    #expect(ProjectInfo.resolve(cwd: "/Users/dev/Development/Kiosk", in: all, devRoot: dev)?.slug == "kiosk")
    #expect(ProjectInfo.resolve(cwd: "/Users/dev/Development/Kiosk", in: all, devRoot: dev)?.info == nil)
    #expect(ProjectInfo.resolve(cwd: "", in: all, devRoot: dev) == nil)
}

@Test func createDefaultsUseTopFolder() {
    let d = ProjectInfo.createDefaults(cwd: "/Users/dev/Development/kiosk/.worktrees/a", devRoot: dev, home: h)
    #expect(d?.slug == "kiosk" && d?.folder == "/Users/dev/Development/kiosk")
    #expect(ProjectInfo.createDefaults(cwd: "/Volumes/x/fjord", devRoot: dev, home: h)?.folder == "/Volumes/x/fjord")
    #expect(ProjectInfo.createDefaults(cwd: dev, devRoot: dev, home: h) == nil)
    #expect(ProjectInfo.createDefaults(cwd: h, devRoot: dev, home: h) == nil)
}

@Test func suggestsPrefixAvoidingCollisions() {
    #expect(ProjectInfo.suggestPrefix(name: "lumen", taken: []) == "lu")
    #expect(ProjectInfo.suggestPrefix(name: "lumen", taken: ["lu"]) == "lm")
    #expect(ProjectInfo.suggestPrefix(name: "lumen", taken: ["lu", "lm", "le", "ln"]) == "lu2")
    #expect(ProjectInfo.suggestPrefix(name: "x", taken: []) == "x2")
    #expect(ProjectInfo.suggestPrefix(name: "", taken: []) == "")
}

@Test func suggestsSessionName() {
    #expect(ProjectInfo.suggestSession(prefix: "lu", running: ["or.pm"]) == "lu.pm")
    #expect(ProjectInfo.suggestSession(prefix: "lu", running: ["lu.pm", "lu.01", "lu.03"]) == "lu.04")
    #expect(ProjectInfo.suggestSession(prefix: "lu", running: ["lu.pm"]) == "lu.01")
}

@Test func writesAndLoadsAll() throws {
    let dir = NSTemporaryDirectory() + "pi-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try ProjectInfo.template(slug: "lumen", folder: "/tmp/lumen", prefix: "lu").write(dir: dir)
    try "x".write(toFile: "\(dir)/Bad.Name.md", atomically: true, encoding: .utf8)
    let all = ProjectInfo.loadAll(dir: dir)
    #expect(all.map(\.slug) == ["lumen"])
    #expect(all.first?.prefix == "lu" && all.first?.folder == "/tmp/lumen")
}
