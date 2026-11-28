import Foundation
import LoupeCore
import Testing

@testable import Loupe

private func piece(_ crit: Double) throws -> Artifact {
  try Artifact(
    setName: "Gladiator's Finale", slot: .flower, main: .hp, level: 0,
    substats: [Substat(.critRate, crit), Substat(.atk, 19.5), Substat(.def, 23.2)])
}

/// The inventory file can change while Loupe is open, as when a backup is put back.
@MainActor
@Test func aChangeStartsFromTheFileOnDisk() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = folder.appending(path: "inventory.json")
  var saved = Inventory()
  let first = saved.save(try piece(2.7))
  let second = saved.save(try piece(3.1))
  try saved.write(to: file)

  let model = Model(inventoryFile: file)
  defer { model.setEnabled(false) }
  model.remove([first])
  #expect(model.inventory.artifacts.map(\.id) == [second])
  #expect(
    try FileManager.default.contentsOfDirectory(
      atPath: folder.appending(path: InventoryBackup.folderName).path
    ).count == 1)

  // Something else saves a piece.
  var other = try Inventory.read(from: file)
  let theirs = other.save(try piece(3.5))
  try other.write(to: file)

  // Undo would put back the inventory from before that piece.
  model.undo()
  #expect(try Inventory.read(from: file).artifacts.map(\.id) == [second, theirs])
  #expect(model.inventory.artifacts.map(\.id) == [second, theirs])

  model.remove([second])
  #expect(try Inventory.read(from: file).artifacts.map(\.id) == [theirs])
}

@MainActor
@Test func aFileMovedAwayIsNotRecreatedFromMemory() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = folder.appending(path: "inventory.json")
  var saved = Inventory()
  let first = saved.save(try piece(2.7))
  saved.save(try piece(3.1))
  try saved.write(to: file)

  let model = Model(inventoryFile: file)
  defer { model.setEnabled(false) }
  try FileManager.default.moveItem(at: file, to: folder.appending(path: "aside.json"))
  model.remove([first])
  #expect(!FileManager.default.fileExists(atPath: file.path))
  #expect(model.issue?.contains("moved or deleted") == true)
  #expect(model.inventory.artifacts.count == 2)
}
