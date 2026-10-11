import ArtifactCore
import Foundation
import Testing

@Suite struct TierExpansionDispatchTests {
  private func artifact(
    _ slot: Slot, _ main: Stat, _ stats: [Substat], level: Int = 20
  ) throws -> Artifact {
    try Artifact(
      setName: "Synthetic off-piece", slot: slot, main: main, level: level, substats: stats)
  }

  private func match(_ piece: Artifact, character: String) throws -> CharacterMatch {
    try #require(CharacterAssessment.evaluate(piece).first { $0.characterID == character })
  }

  @Test func unfinishedCurrentIsAbsentAndMedianIsNotTheCeiling() throws {
    let piece = try artifact(
      .sands, .hpPercent,
      [
        Substat(.critRate, 15.56), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 12.96),
      ], level: 16)
    let result = try match(piece, character: "furina")
    let grades = try #require(result.grades)
    #expect(grades.current == nil)
    #expect(grades.p50 == .a)
    #expect(grades.p90 == .s)
    #expect(grades.bestPossible == .s)
    #expect(grades.chanceOfAOrBetter == 1)
    #expect(result.potential?.summary.p50Score == 5)
    #expect(result.potential?.summary.bestPossibleScore == 6)
  }

  @Test func aOrBetterUsesExactMassRatherThanMedianOrCeiling() throws {
    let piece = try artifact(
      .sands, .hpPercent,
      [
        Substat(.critRate, 11.67), Substat(.critDamage, 7.77), Substat(.def, 46.30),
        Substat(.energyRecharge, 12.96),
      ], level: 16)
    let result = try match(piece, character: "furina")
    let grades = try #require(result.grades)
    #expect(
      result.potential?.distribution == [
        4000: 0.5, 4700: 0.125, 4800: 0.125,
        4900: 0.125, 5000: 0.125,
      ])
    #expect(grades.current == nil)
    #expect(grades.p50 == .b)
    #expect(grades.p90 == .a)
    #expect(grades.bestPossible == .a)
    #expect(grades.chanceOfAOrBetter == 0.25)
  }

  @Test func identicalCoreWeightsDoNotGrantAnotherRoleACalibrationCell() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.hpPercent, 23.32), Substat(.critRate, 7.78), Substat(.critDamage, 7.77),
        Substat(.energyRecharge, 12.96),
      ])
    let results = CharacterAssessment.evaluate(piece)
    let furina = try #require(results.first { $0.characterID == "furina" })
    let neuvillette = try #require(results.first { $0.characterID == "neuvillette" })
    #expect(furina.profile.weights == neuvillette.profile.weights)
    #expect(furina.grades?.current == .s)
    #expect(neuvillette.grades == nil)
    #expect(
      Set(results.filter { $0.grades != nil }.map(\.characterID))
        == ["furina", "itto", "kuki-shinobu"])
  }

  @Test func neighboringEligibleMainsRemainUngradedAndExcludedMainsDoNotMatch() throws {
    let erSands = try artifact(
      .sands, .energyRecharge,
      [
        Substat(.hpPercent, 34.98), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
        Substat(.def, 23.15),
      ])
    let furina = try match(erSands, character: "furina")
    #expect(furina.potential?.currentScore == 8)
    #expect(furina.grades == nil)
    let hpCirclet = try artifact(
      .circlet, .hpPercent,
      [
        Substat(.critRate, 23.34), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 6.48),
      ])
    #expect(!CharacterAssessment.evaluate(hpCirclet).contains { $0.characterID == "furina" })
    let defGoblet = try artifact(
      .goblet, .defPercent,
      [
        Substat(.critRate, 23.34), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 6.48),
      ])
    #expect(!CharacterAssessment.evaluate(defGoblet).contains { $0.characterID == "itto" })
  }

  @Test(arguments: [Slot.sands, .goblet, .circlet])
  func emMainsStillHaveNoGradeOrScalarComparison(slot: Slot) throws {
    let piece = try artifact(
      slot, .elementalMastery,
      [
        Substat(.atk, 116.70), Substat(.critRate, 3.89), Substat(.def, 23.15),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try match(piece, character: "kuki-shinobu")
    #expect(result.grades == nil)
    #expect(result.potential == nil)
    #expect(result.potentialUnavailableReason?.contains("no eligible core substats") == true)
  }

  @Test func savedLeadersUseEachFixedRoleWithoutChangingIntrinsicGrades() throws {
    let candidate = try artifact(
      .flower, .hp,
      [
        Substat(.hpPercent, 23.32), Substat(.defPercent, 7.29), Substat(.critRate, 7.78),
        Substat(.critDamage, 7.77),
      ])
    let hpHeavy = try artifact(
      .flower, .hp,
      [
        Substat(.hpPercent, 29.15), Substat(.defPercent, 7.29), Substat(.critRate, 3.89),
        Substat(.critDamage, 7.77),
      ])
    let defHeavy = try artifact(
      .flower, .hp,
      [
        Substat(.hpPercent, 5.83), Substat(.defPercent, 36.45), Substat(.critRate, 3.89),
        Substat(.critDamage, 7.77),
      ])
    let linked = try candidate.withID(UUID())
    let results = CharacterAssessment.evaluate(
      candidate, inventory: [hpHeavy, defHeavy, linked], scope: .offPiece, excluding: linked.id)
    let furina = try #require(results.first { $0.characterID == "furina" })
    let itto = try #require(results.first { $0.characterID == "itto" })
    #expect(furina.potential?.leaders.first?.id == hpHeavy.id)
    #expect(itto.potential?.leaders.first?.id == defHeavy.id)
    #expect(furina.potential?.comparisonCount == 2)
    #expect(itto.potential?.comparisonCount == 2)
    #expect(furina.potential?.currentScore == 7)
    #expect(itto.potential?.currentScore == 4)
    #expect(furina.potential?.rankChances.first?.probability == 1)
    #expect(itto.potential?.rankChances.first?.probability == 0)
    #expect(furina.grades?.current == .s)
    #expect(itto.grades?.current == .b)
    #expect(furina.grades?.current == (try match(candidate, character: "furina")).grades?.current)
    #expect(itto.grades?.current == (try match(candidate, character: "itto")).grades?.current)
  }
}
