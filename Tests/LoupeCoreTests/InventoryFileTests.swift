import Foundation
import LoupeCore
import Testing

/// Every build shares one inventory file, so none may lose what another wrote.
@Suite final class InventoryFileTests {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  var file: URL { folder.appending(path: "inventory.json") }

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: folder) }

  private func object(_ url: URL) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
  }

  private let newer = """
    {
      "format" : 2,
      "artifacts" : [
        {
          "id" : "068D60FD-019E-466A-AE02-47D646A17480", "level" : 0, "main" : "atk",
          "rarity" : 5, "rule" : "ordinary", "setName" : "Night of the Sky's Unveiling",
          "slot" : "plume",
          "substats" : [
            { "key" : "hp", "value" : 209 }, { "key" : "def", "value" : 16 },
            { "key" : "eleMas", "value" : 19 }
          ],
          "unactivated" : { "key" : "critDMG_", "value" : 6.2 },
          "locked" : true, "note" : { "text" : "for Furina", "tags" : [1, null, "x"] }
        },
        {
          "id" : "9A0E1D7B-3E54-4B0B-8E2A-0B6C3C1F7E11", "level" : 0, "main" : "atk",
          "rarity" : 6, "rule" : "ordinary", "setName" : "A Set From Later",
          "slot" : "plume", "substats" : []
        }
      ]
    }
    """

  @Test func keepsWhatANewerBuildWroteThroughAnOlderBuildsSave() throws {
    try newer.write(to: file, atomically: true, encoding: .utf8)
    var inventory = try Inventory.read(from: file)
    #expect(inventory.artifacts.count == 1)
    #expect(inventory.unreadable.count == 1)
    let piece = try Artifact(
      setName: "Gladiator's Finale", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atk, 19.5), Substat(.def, 23.2)])
    inventory.save(piece)
    try inventory.write(to: file)

    let saved = try object(file)
    #expect(saved["format"] as? Int == 2)
    let records = try #require(saved["artifacts"] as? [[String: Any]])
    #expect(records.count == 3)
    let kept = try #require(
      records.first { $0["id"] as? String == "068D60FD-019E-466A-AE02-47D646A17480" })
    #expect(kept["locked"] as? Bool == true)
    let note = try #require(kept["note"] as? [String: Any])
    #expect(note["text"] as? String == "for Furina")
    #expect((note["tags"] as? [Any])?.count == 3)
    #expect(records.contains { $0["setName"] as? String == "A Set From Later" })
    // Whole numbers stay whole.
    #expect(try String(contentsOf: file, encoding: .utf8).contains("\"value\" : 209\n"))

    let again = try Inventory.read(from: file)
    #expect(again.artifacts.count == 2)
    #expect(again.unreadable == inventory.unreadable)
  }

  @Test func dropsUnknownFieldsWithTheirRecord() throws {
    try newer.write(to: file, atomically: true, encoding: .utf8)
    var inventory = try Inventory.read(from: file)
    inventory.remove(inventory.artifacts[0].id)
    try inventory.write(to: file)
    #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("locked"))
  }

  @Test func backsUpAndKeepsOnlyTheNewestCopies() throws {
    let backups = folder.appending(path: InventoryBackup.folderName)
    #expect(try InventoryBackup.copy(file, into: backups, label: "1.0.0") == nil)
    try newer.write(to: file, atomically: true, encoding: .utf8)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    for minute in 0..<4 {
      try InventoryBackup.copy(
        file, into: backups, label: "1.0.0 dev", at: start.addingTimeInterval(Double(minute) * 60),
        keep: 3)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: backups.path).sorted()
    #expect(
      names == [
        "inventory 2027-01-15 080100.000Z 1.0.0 dev.json",
        "inventory 2027-01-15 080200.000Z 1.0.0 dev.json",
        "inventory 2027-01-15 080300.000Z 1.0.0 dev.json",
      ])
    #expect(try Data(contentsOf: backups.appending(path: names[2])) == Data(contentsOf: file))
  }

  @Test func writesUnchangedRecordsBackExactlyAndKeepsWholeNumbersExact() throws {
    let record = """
      {
        "artifacts" : [
          {
            "id" : "068D60FD-019E-466A-AE02-47D646A17480", "level" : 0, "main" : "atk",
            "rarity" : 5, "rule" : "ordinary", "setName" : "Night of the Sky's Unveiling",
            "slot" : "plume",
            "substats" : [
              { "key" : "hp", "value" : 209, "rolls" : [9007199254740993] },
              { "key" : "def", "value" : 16 }, { "key" : "eleMas", "value" : 19 }
            ]
          }
        ]
      }
      """
    try record.write(to: file, atomically: true, encoding: .utf8)
    var inventory = try Inventory.read(from: file)
    let piece = try Artifact(
      setName: "Gladiator's Finale", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atk, 19.5), Substat(.def, 23.2)])
    inventory.save(piece)
    try inventory.write(to: file)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("9007199254740993"))
  }

  @Test func refusesAnIDAReadableAndAnUnreadableRecordShare() throws {
    let shared = newer.replacingOccurrences(
      of: "9A0E1D7B-3E54-4B0B-8E2A-0B6C3C1F7E11", with: "068D60FD-019E-466A-AE02-47D646A17480")
    try shared.write(to: file, atomically: true, encoding: .utf8)
    #expect(throws: ArtifactError.self) { try Inventory.read(from: file) }
  }
}
