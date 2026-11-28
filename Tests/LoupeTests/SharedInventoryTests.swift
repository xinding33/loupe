import Foundation
import LoupeCore
import Testing

@testable import Loupe

private func piece(_ crit: Double) throws -> Artifact {
  try Artifact(
    setName: "Gladiator's Finale", slot: .flower, main: .hp, level: 0,
    substats: [Substat(.critRate, crit), Substat(.atk, 19.5), Substat(.def, 23.2)])
}

/// A release and a development build can run at once, both saving the one inventory file.
@MainActor
@Test func aChangeKeepsWhatAnotherCopySavedMeanwhile() throws {
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

  // The other copy saves a piece of its own.
  var other = try Inventory.read(from: file)
  let theirs = other.save(try piece(3.5))
  try other.write(to: file)

  // Undo would put back the inventory from before the other copy's piece.
  model.undo()
  #expect(try Inventory.read(from: file).artifacts.map(\.id) == [second, theirs])
  #expect(model.inventory.artifacts.map(\.id) == [second, theirs])

  model.remove([second])
  #expect(try Inventory.read(from: file).artifacts.map(\.id) == [theirs])
}
