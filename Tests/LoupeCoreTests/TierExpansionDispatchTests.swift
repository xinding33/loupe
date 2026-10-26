import Foundation
import LoupeCore
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

  @Test func unfinishedGradeUsesTheExpectedScoreNotTheMedianOrCeiling() throws {
    let piece = try artifact(
      .sands, .hpPercent,
      [
        Substat(.critRate, 15.56), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 12.96),
      ], level: 16)
    let result = try match(piece, character: "furina")
    let grades = try #require(result.grades)
    let potential = try #require(result.potential)
    // Four CR rolls, one CD and two quarter-weight ER rolls, with one upgrade left.
    #expect(potential.currentScore == 5.5)
    #expect(potential.summary.p50Score == 5.75)
    #expect(potential.summary.bestPossibleScore == 6.5)
    let rarity = try DropRarity(slot: .sands, main: .hpPercent, profile: result.profile)
    let cutoffs = RollGrade.cutoffs(rarity, profile: result.profile)
    #expect(grades.grade == RollGrade.tier(potential.expectedScore * 1000, cutoffs: cutoffs))
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
    let distribution = try #require(result.potential?.distribution)
    #expect(
      distribution == [
        4500: 0.25, 4675: 0.0625, 4700: 0.0625, 4725: 0.0625, 4750: 0.0625,
        5200: 0.125, 5300: 0.125, 5400: 0.125, 5500: 0.125,
      ])
    let rarity = try DropRarity(slot: .sands, main: .hpPercent, profile: result.profile)
    let a = try #require(
      RollGrade.cutoffs(rarity, profile: result.profile).first { $0.tier == .a }
    ).minimum
    #expect(
      grades.chanceOfAOrBetter
        == distribution.filter { Double($0.key) >= a }.values.reduce(0, +))
  }

  @Test func identicalCoreWeightsShareOneRarityGrade() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.hpPercent, 23.32), Substat(.critRate, 7.78), Substat(.critDamage, 7.77),
        Substat(.energyRecharge, 12.96),
      ])
    let results = CharacterAssessment.evaluate(piece)
    let furina = try #require(results.first { $0.characterID == "furina" })
    let yelan = try #require(results.first { $0.characterID == "yelan" })
    #expect(furina.profile.weights == yelan.profile.weights)
    #expect(furina.grades?.grade == .s)
    #expect(yelan.grades?.grade == furina.grades?.grade)
    #expect(yelan.grades?.rarityShare == furina.grades?.rarityShare)
  }

  @Test func neighboringEligibleMainsRemainUngradedAndExcludedMainsDoNotMatch() throws {
    let erSands = try artifact(
      .sands, .energyRecharge,
      [
        Substat(.hpPercent, 34.98), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
        Substat(.def, 23.15),
      ])
    let furina = try match(erSands, character: "furina")
    #expect(furina.potential?.currentScore == 7.1)
    #expect(furina.grades?.grade == .s)
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
    #expect(furina.potential?.currentScore == 6.4)
    #expect(itto.potential?.currentScore == 3.85)
    #expect(furina.potential?.rankChances.first?.probability == 1)
    #expect(itto.potential?.rankChances.first?.probability == 0)
    #expect(furina.grades?.grade == .s)
    #expect(itto.grades?.grade == .a)
    #expect(furina.grades?.grade == (try match(candidate, character: "furina")).grades?.grade)
    #expect(itto.grades?.grade == (try match(candidate, character: "itto")).grades?.grade)
  }
}
