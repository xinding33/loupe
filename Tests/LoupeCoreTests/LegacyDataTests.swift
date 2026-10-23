import Foundation
import LoupeCore
import Testing

@Suite final class LegacyDataTests {
  let support: URL
  var old: URL { support.appending(path: "ArtifactLens") }
  var new: URL { support.appending(path: "Loupe") }

  init() throws {
    support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: support) }

  func write(_ text: String, to file: URL) throws {
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func read(_ file: URL) throws -> String { try String(contentsOf: file, encoding: .utf8) }

  @Test func movesTheOldFolderOnce() throws {
    try write("old", to: old.appending(path: "inventory.json"))
    let move = try LegacyData.moveFolder(in: support, to: new)
    #expect(move == LegacyData.Move(moved: ["."], kept: []))
    #expect(try read(new.appending(path: "inventory.json")) == "old")
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(try LegacyData.moveFolder(in: support, to: new) == LegacyData.Move())
  }

  @Test func finishesAMoveIntoAFolderLoupeAlreadyCreated() throws {
    // A failed move, then a launch that created the new folder and a recording in it.
    try write("old", to: old.appending(path: "inventory.json"))
    try write("a", to: old.appending(path: "Diagnostics/A/000.png"))
    try write("b", to: new.appending(path: "Diagnostics/B/000.png"))
    let move = try LegacyData.moveFolder(in: support, to: new)
    #expect(move.moved == ["Diagnostics/A", "inventory.json"])
    #expect(move.kept.isEmpty)
    #expect(try read(new.appending(path: "inventory.json")) == "old")
    #expect(try read(new.appending(path: "Diagnostics/A/000.png")) == "a")
    #expect(try read(new.appending(path: "Diagnostics/B/000.png")) == "b")
    #expect(!FileManager.default.fileExists(atPath: old.path))
  }

  @Test func neverReplacesAnExistingFile() throws {
    try write("old", to: old.appending(path: "inventory.json"))
    try write("new", to: new.appending(path: "inventory.json"))
    let move = try LegacyData.moveFolder(in: support, to: new)
    #expect(move == LegacyData.Move(moved: [], kept: ["inventory.json"]))
    #expect(try read(new.appending(path: "inventory.json")) == "new")
    #expect(try read(old.appending(path: "inventory.json")) == "old")
  }

  @Test func copiesOnlyMissingSettings() throws {
    let suite = "LoupeCoreTests.legacy.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("option+1", forKey: "expandShortcut")
    let copied = LegacyData.copySettings(
      ["expandShortcut": "option+`", "enableShortcut": "option+shift+`"], into: defaults)
    #expect(copied == ["enableShortcut"])
    #expect(defaults.string(forKey: "expandShortcut") == "option+1")
    #expect(defaults.string(forKey: "enableShortcut") == "option+shift+`")
  }
}
