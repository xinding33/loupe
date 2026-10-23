import Foundation
import LoupeCore
import Testing

@testable import Loupe

@Test func inventoryCoverageCountsOnlyFinishedPiecesAndKeepsRealDuplicates() throws {
  let piece = try Artifact(
    setName: "Ocean-Hued Clam", slot: .circlet, main: .healing, level: 20,
    substats: [
      Substat(.hpPercent, 35.0), Substat(.energyRecharge, 6.5), Substat(.atk, 19),
      Substat(.def, 23),
    ])
  let starter = try Artifact(
    setName: "Ocean-Hued Clam", slot: .circlet, main: .healing, level: 0,
    substats: [Substat(.hpPercent, 5.8), Substat(.energyRecharge, 6.5), Substat(.atk, 19)])
  let categories = InventoryCategory.summarize([piece, try piece.withID(UUID()), starter])
  #expect(categories.first { $0.slot == .circlet && $0.main == .healing }?.count == 2)
  #expect(categories.first { $0.slot == .goblet && $0.main == .hydroDamage }?.count == 0)
  #expect(categories.reduce(0) { $0 + $1.count } == 2)
  #expect(!categories.contains { $0.slot == .flower && $0.main == .critRate })
}
