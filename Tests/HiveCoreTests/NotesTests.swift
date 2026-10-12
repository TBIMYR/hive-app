import Foundation
import Testing
@testable import HiveCore

private func tempRoot() -> String { NSTemporaryDirectory() + "notes-\(UUID().uuidString)" }

@Test func notesAreOneNotepadPerSession() {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    #expect(Notes.read(root: root, session: "lu.01") == "")
    #expect(Notes.sessions(root: root).isEmpty)

    Notes.write(root: root, session: "lu.01", text: "  first\nline two \n")
    Notes.write(root: root, session: "or.pm", text: "other session")
    #expect(Notes.read(root: root, session: "lu.01") == "first\nline two")
    #expect(Notes.sessions(root: root) == ["lu.01", "or.pm"])
    #expect((try? String(contentsOfFile: "\(root)/lu.01.md", encoding: .utf8)) == "first\nline two\n")

    // clearing the text removes the notepad
    Notes.write(root: root, session: "lu.01", text: " \n")
    #expect(Notes.sessions(root: root) == ["or.pm"])
    #expect(!FileManager.default.fileExists(atPath: "\(root)/lu.01.md"))
}

@Test func notesAppendBelowWithALine() {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    Notes.append(root: root, session: "lu.01", text: "first\n")
    #expect(Notes.read(root: root, session: "lu.01") == "first")
    Notes.append(root: root, session: "lu.01", text: "second")
    Notes.append(root: root, session: "lu.01", text: "  ")
    #expect(Notes.read(root: root, session: "lu.01") == "first\n\n---\n\nsecond")
}

@Test func notesRejectUnsafeNames() {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    Notes.write(root: root, session: "../lu", text: "x")
    Notes.write(root: root, session: "lu/01", text: "x")
    Notes.append(root: root, session: "", text: "x")
    #expect(Notes.read(root: root, session: "../lu") == "")
    #expect(Notes.validName("lu.pm") && Notes.validName("ki_02#a-b"))
    #expect(!FileManager.default.fileExists(atPath: root))
}

@Test func notesMigrateTheEarlierFilePerNoteFolders() throws {
    let root = tempRoot()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let fm = FileManager.default
    try fm.createDirectory(atPath: "\(root)/lu.01", withIntermediateDirectories: true)
    try "newer\n".write(toFile: "\(root)/lu.01/20261012-141502-4242.md", atomically: true, encoding: .utf8)
    try "older\n".write(toFile: "\(root)/lu.01/20261011-090000-001.md", atomically: true, encoding: .utf8)
    try "".write(toFile: "\(root)/lu.01/20261012-150000-002.md", atomically: true, encoding: .utf8)
    try "x".write(toFile: "\(root)/lu.01/.cc-note.tmp", atomically: true, encoding: .utf8)
    // already written by the new cc-note before the app migrated
    try "appended\n".write(toFile: "\(root)/lu.01.md", atomically: true, encoding: .utf8)
    try "untouched\n".write(toFile: "\(root)/or.pm.md", atomically: true, encoding: .utf8)

    Notes.migrate(root: root)
    #expect(Notes.read(root: root, session: "lu.01") == "older\n\n---\n\nnewer\n\n---\n\nappended")
    #expect(Notes.read(root: root, session: "or.pm") == "untouched")
    #expect(!fm.fileExists(atPath: "\(root)/lu.01"))
    #expect(fm.fileExists(atPath: "\(root)/.old/lu.01/20261011-090000-001.md"))
    // running it again changes nothing
    Notes.migrate(root: root)
    #expect(Notes.read(root: root, session: "lu.01") == "older\n\n---\n\nnewer\n\n---\n\nappended")
    #expect(Notes.sessions(root: root) == ["lu.01", "or.pm"])
}
