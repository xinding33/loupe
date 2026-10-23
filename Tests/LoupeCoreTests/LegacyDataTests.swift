import Foundation
import LoupeCore
import Testing

@Suite final class LegacyDataTests {
  let support: URL

  init() throws {
    support = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: support) }

  @Test func movesTheOldFolderOnce() throws {
    let old = support.appending(path: "ArtifactLens")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try Data("[]".utf8).write(to: old.appending(path: "inventory.json"))
    let new = support.appending(path: "Loupe")
    #expect(try LegacyData.moveFolder(in: support, to: new))
    #expect(FileManager.default.fileExists(atPath: new.appending(path: "inventory.json").path))
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(try !LegacyData.moveFolder(in: support, to: new))
  }

  @Test func neverReplacesAnExistingFolder() throws {
    let old = support.appending(path: "ArtifactLens")
    let new = support.appending(path: "Loupe")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
    #expect(try !LegacyData.moveFolder(in: support, to: new))
    #expect(FileManager.default.fileExists(atPath: old.path))
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
