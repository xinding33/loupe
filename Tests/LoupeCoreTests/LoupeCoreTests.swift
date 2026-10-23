import Foundation
import LoupeCore
import Testing

private let card = """
  Holy Crown of the Believer
  Circlet of Logos
  CRIT DMG
  9.3%
  +0
  ATK+18
  HP+4.1%
  Energy Recharge+5.2%
  DEF+5.1% (unactivated)
  Silken Moon's Serenade:
  2-Piece Set: Energy Recharge +20%.
  """

@Test func readsTheObservedGeForceCardAndKeepsTheInactiveRollSeparate() throws {
  let artifact = try CardParser.parse(card, fiveStarsConfirmed: true)
  #expect(artifact.slot == .circlet)
  #expect(artifact.main == .critDamage)
  #expect(artifact.substats.count == 3)
  #expect(artifact.unactivated == Substat(.defPercent, 5.1))
  let result = try Potential.evaluate(
    artifact, profile: Profile("ER", weights: [.energyRecharge: 100]), inventory: [],
    scope: .offPiece)
  #expect(result.upgradesRemaining == 4)
  #expect(abs(result.maximumScore - result.currentScore - 4) < 0.001)
  #expect(result.bestRank == nil)
  #expect(result.rankChances.isEmpty)
}

@Test func aFourLineStarterGetsFiveRandomUpgrades() throws {
  let artifact = try flower(level: 0, crit: 3.9)
  let potential = try Potential.evaluate(
    artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)
  #expect(potential.upgradesRemaining == 5)
  #expect(abs(potential.maximumScore - potential.currentScore - 5) < 0.001)
  #expect(abs(potential.distribution.values.reduce(0, +) - 1) < 1e-10)
  #expect(abs(potential.expectedScore - potential.currentScore - 1.0625) < 1e-10)
}

@Test func aNonCheckpointLevelStillIncludesTheNextEvent() throws {
  let artifact = try flower(level: 19, crit: 19.5)
  let result = try Potential.evaluate(
    artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)
  #expect(artifact.nextCheckpoint == 20)
  #expect(result.upgradesRemaining == 1)
}

@Test func oneRemainingRollHasKnownTopRankOddsAndExcludesTheLinkedPiece() throws {
  let candidate = try flower(level: 16, crit: 19.5)
  let leader = try flower(level: 20, crit: 19.5, atk: 38.9)
  let result = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: [leader, candidate], scope: .offPiece)
  #expect(result.comparisonCount == 1)
  #expect(result.bestRank == 1)
  #expect(result.rankChances.first?.probability == 1)
  #expect(result.chanceToBeatBest == 0.25)
  let maxed = try Potential.evaluate(
    leader, profile: Profile.presets[0], inventory: [leader], scope: .offPiece)
  #expect(maxed.comparisonCount == 0)
  #expect(maxed.upgradesRemaining == 0)
}

@Test func topTwoIsCumulativeAndTiesDoNotCountAsStrictWins() throws {
  let candidate = try flower(level: 16, crit: 15.6, atk: 38.9)
  let leader = try flower(level: 20, crit: 19.5, atk: 38.9)
  let second = try flower(level: 20, crit: 15.6, atk: 58.4)
  let result = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: [leader, second], scope: .offPiece)
  #expect(result.bestRank == 1)
  #expect(result.rankChances[0].probability == 0.0625)
  #expect(result.rankChances[1].probability == 1)
  #expect(result.chanceToBeatBest == 0)
}

@Test func allSetsRetainsOffPiecesWhileSameSetNarrowsThePool() throws {
  let candidate = try flower(level: 0, crit: 3.9)
  let other = try flower(level: 20, crit: 23.3, set: "GladiatorsFinale")
  let inventory = [other]
  let off = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: inventory, scope: .offPiece)
  let on = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: inventory, scope: .sameSet)
  #expect(off.comparisonCount == 1)
  #expect(on.comparisonCount == 0)
  #expect(Artifact.normalizeSet("Gladiator's Finale") == other.setKey)
}

@Test func missingFourthStatAndSpecialRulesDoNotProduceOrdinaryOdds() throws {
  let missing = try Artifact(
    setName: "Test", slot: .flower, main: .hp, level: 0,
    substats: [Substat(.critRate, 3.9), Substat(.atk, 19), Substat(.def, 23)])
  #expect(throws: ArtifactError.self) {
    try Potential.evaluate(missing, profile: Profile.presets[0], inventory: [], scope: .offPiece)
  }
  let special = try CardParser.parse(card, fiveStarsConfirmed: true, rule: .special)
  #expect(throws: ArtifactError.self) {
    try Potential.evaluate(special, profile: Profile.presets[0], inventory: [], scope: .offPiece)
  }
}

@Test func rejectsUnreadableImpossibleOrNonFiveStarCards() {
  #expect(throws: ArtifactError.self) { try CardParser.parse(card, fiveStarsConfirmed: false) }
  #expect(throws: ArtifactError.self) {
    try CardParser.parse("Loading...", fiveStarsConfirmed: true)
  }
  #expect(throws: ArtifactError.self) {
    try CardParser.parse(
      card.replacingOccurrences(of: "5.2%", with: "52%"), fiveStarsConfirmed: true)
  }
  #expect(throws: ArtifactError.self) {
    try CardParser.parse(
      card.replacingOccurrences(of: "+0\n", with: "+20\n"), fiveStarsConfirmed: true)
  }
  #expect(throws: ArtifactError.self) {
    try Artifact(
      setName: "Test", slot: .flower, main: .critRate, level: 0,
      substats: [Substat(.atk, 19), Substat(.def, 23), Substat(.hpPercent, 5.8)])
  }
}

@Test func aSavedUpgradeReplacesTheRecordAndUnrelatedPiecesCannotOverwriteIt() throws {
  var inventory = Inventory()
  let artifact = try flower(level: 0, crit: 3.9)
  let id = inventory.save(artifact)
  #expect(inventory.save(try flower(level: 0, crit: 3.9)) == id)
  #expect(inventory.artifacts.count == 1)
  try inventory.update(id, with: flower(level: 4, crit: 7.8))
  #expect(inventory.artifacts.count == 1)
  #expect(inventory.artifacts[0].level == 4)
  #expect(inventory.artifacts[0].id == id)
  #expect(throws: ArtifactError.self) {
    try inventory.update(id, with: flower(level: 8, crit: 11.7, set: "Other"))
  }
  inventory.save(try flower(level: 4, crit: 7.8), allowIdenticalCopy: true)
  #expect(inventory.artifacts.count == 2)
}

@Test func persistsValidatedInventoryAndDoesNotLoadCorruptStats() throws {
  let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = folder.appending(path: "inventory.json")
  var inventory = Inventory()
  inventory.save(try flower(level: 0, crit: 3.9))
  try inventory.write(to: file)
  #expect(try Inventory.read(from: file).artifacts == inventory.artifacts)
  let corrupted = try String(contentsOf: file, encoding: .utf8).replacingOccurrences(
    of: "3.9", with: "99.9")
  try corrupted.write(to: file, atomically: true, encoding: .utf8)
  #expect(throws: ArtifactError.self) { try Inventory.read(from: file) }
}

@Test func importsGOODAndDoesNotAssumeUnfinishedArtifactsHaveOrdinaryRolls() throws {
  let json =
    #"{"format":"GOOD","artifacts":[{"setKey":"SilkenMoonsSerenade","slotKey":"circlet","mainStatKey":"critDMG_","rarity":5,"level":0,"substats":[{"key":"atk","value":18},{"key":"hp_","value":4.1},{"key":"enerRech_","value":5.2}],"unactivatedSubstats":[{"key":"def_","value":5.1}]}]}"#
  let result = try Inventory.importGOOD(Data(json.utf8))
  #expect(result.artifacts.count == 1)
  #expect(result.artifacts[0].unactivated == Substat(.defPercent, 5.1))
  #expect(result.artifacts[0].rule == .special)
  #expect(result.skipped == 0)
}

@Test func inventoryImportPreservesRealDuplicatesWithoutDuplicatingARepeatedImport() throws {
  let first = try flower(level: 20, crit: 23.3)
  let identical = try flower(level: 20, crit: 23.3)
  var inventory = Inventory()
  try inventory.merge([first, identical])
  #expect(inventory.artifacts.count == 2)
  try inventory.merge([first, identical])
  #expect(inventory.artifacts.count == 2)
  #expect(Set(inventory.artifacts.map(\.id)).count == 2)
}

@Test func matchingSetDoesNotCompareDifferentSlotsOrMainStats() throws {
  let candidate = try CardParser.parse(card, fiveStarsConfirmed: true)
  let other = try flower(level: 20, crit: 23.3, set: candidate.setName)
  let result = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: [other], scope: .sameSet)
  #expect(result.comparisonCount == 0)
  #expect(result.rankChances.isEmpty)
  #expect(result.maximumScore == 0)
}

@Test func capturedPlumeMatchesIndependentlyCountedUpgradeOdds() throws {
  let candidate = try Artifact(
    setName: "Night of the Sky's Unveiling", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.def, 21), Substat(.hpPercent, 4.1), Substat(.critDamage, 6.2)],
    unactivated: Substat(.critRate, 3.1))
  let first = try Artifact(
    setName: "Obsidian Codex", slot: .plume, main: .atk, level: 20,
    substats: [
      Substat(.critDamage, 5.4), Substat(.elementalMastery, 23), Substat(.critRate, 17.5),
      Substat(.def, 16),
    ])
  let second = try Artifact(
    setName: "Golden Troupe", slot: .plume, main: .atk, level: 20,
    substats: [
      Substat(.energyRecharge, 5.8), Substat(.hpPercent, 5.8), Substat(.def, 44),
      Substat(.critDamage, 25.7),
    ])
  let result = try Potential.evaluate(
    candidate, profile: Profile.presets[0], inventory: [first, second], scope: .offPiece)
  #expect(result.maximumScore == 5.6)
  // Four useful rolls with tier sum >=36: 66 of 4096 equally weighted outcomes.
  #expect(result.rankChances[0].probability == 66.0 / 4096)
  #expect(result.rankChances[1].probability == 0.546875)
  #expect(result.chanceToBeatBest == 35.0 / 4096)
}

@Test func enhancementInheritsOnlyVerifiedIdentityAndActivatesTheFourthStat() throws {
  let previous = try CardParser.parse(card, fiveStarsConfirmed: true)
  let screen = """
    Circlet of Logos / Holy Crown of the Believer
    +4
    CRIT DMG+19.9%
    ATK+18
    HP+4.1%
    Energy Recharge+5.2%
    DEF+5.1%
    """
  let updated = try CardParser.parseEnhancement(
    screen, previous: previous, pieceName: "Holy Crown of the Believer")
  #expect(updated.level == 4)
  #expect(updated.unactivated == nil)
  #expect(updated.substats.count == 4)
  #expect(updated.id == previous.id)
  let result = try Potential.evaluate(
    updated, profile: Profile("ER", weights: [.energyRecharge: 100]), inventory: [],
    scope: .offPiece)
  #expect(result.upgradesRemaining == 4)
  #expect(throws: ArtifactError.self) {
    try CardParser.parseEnhancement(screen, previous: previous, pieceName: "Another Circlet")
  }
}

@Test func enhancementRejectsAnExtraRollAtActivationAndUnchangedStatsAfterARoll() throws {
  let previous = try CardParser.parse(card, fiveStarsConfirmed: true)
  let extra = try Artifact(
    setName: previous.setName, slot: previous.slot, main: previous.main, level: 4,
    substats: [
      Substat(.atk, 18), Substat(.hpPercent, 4.1), Substat(.energyRecharge, 10.4),
      Substat(.defPercent, 5.1),
    ])
  #expect(throws: ArtifactError.self) { try previous.upgraded(to: extra) }
  let fourLine = try flower(level: 0, crit: 3.9)
  let unchanged = try flower(level: 4, crit: 3.9)
  #expect(throws: ArtifactError.self) { try fourLine.upgraded(to: unchanged) }
}

private func flower(level: Int, crit: Double, atk: Double = 19.5, set: String = "Deepwood Memories")
  throws -> Artifact
{
  try Artifact(
    setName: set, slot: .flower, main: .hp, level: level,
    substats: [
      Substat(.critRate, crit), Substat(.atk, atk), Substat(.def, 23.2), Substat(.hpPercent, 5.8),
    ])
}
