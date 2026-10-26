import Foundation
import Testing

@testable import LoupeCore

@Suite struct RollGradeTests {
  private func role(_ roleID: String) throws -> CharacterRole {
    try #require(CharacterRoles.all.first { $0.roleID == roleID })
  }

  private func grade(_ piece: Artifact, _ roleID: String) throws -> CharacterGradeSummary {
    let match = try #require(
      CharacterAssessment.evaluate(piece, roles: [try role(roleID)]).first)
    return try #require(match.grades)
  }

  private func plume(_ lines: [Substat], unactivated: Substat? = nil) throws -> Artifact {
    try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0, substats: lines,
      unactivated: unactivated)
  }

  @Test func damageRolesDiscountTheirScalingStatAndSupportsDoNot() throws {
    #expect(
      try role("arlecchino.atk-crit").profile.weights == [
        .critRate: 100, .critDamage: 100, .atkPercent: 75, .energyRecharge: 25,
      ])
    #expect(
      try role("furina.off-field-hp").profile.weights == [
        .critRate: 100, .critDamage: 100, .hpPercent: 85, .energyRecharge: 25,
      ])
    #expect(
      try role("kuki-shinobu.hyperbloom").profile.weights == [
        .elementalMastery: 100, .energyRecharge: 25, .hpPercent: 25,
      ])
    #expect(
      RollWeights.weights(useful: [.atkPercent, .energyRecharge], secondary: [.critRate]) == [
        .atkPercent: 100, .energyRecharge: 100, .critRate: 25,
      ])
  }

  @Test func referenceExamplesSetRisingShares() {
    let examples = RollGrade.examples(main: .atk, profile: RollGrade.reference)
    #expect(examples.map(\.score) == [5287.5, 3100, 2712.5, 1550])
    let shares = RollGrade.shares.map(\.share)
    #expect(RollGrade.shares.map(\.tier) == [.s, .a, .b, .c])
    #expect(zip(shares, shares.dropFirst()).allSatisfy { $0 < $1 })
    // About 1 in 100 finished plumes is S and 1 in 5 A or better.
    #expect(shares[0] > 0.005 && shares[0] < 0.02)
    #expect(shares[1] > 0.15 && shares[1] < 0.25)
  }

  @Test func theUsersRulesOfThumbGradeAsDescribed() throws {
    let atkCrit = "arlecchino.atk-crit"
    // Double crit with ATK% and HP at +4, from the user's report.
    let reported = try grade(
      plume(
        [Substat(.critRate, 3.9), Substat(.atkPercent, 5.3), Substat(.critDamage, 7.8)],
        unactivated: Substat(.hp, 269)), atkCrit)
    #expect(reported.grade == .a)
    #expect((reported.chanceOfAOrBetter ?? 0) > 0.99)
    // The four best lines at their lowest rolls.
    let perfect = try plume([
      Substat(.critRate, 2.72), Substat(.atkPercent, 4.08), Substat(.critDamage, 5.44),
      Substat(.energyRecharge, 4.53),
    ])
    #expect(try grade(perfect, atkCrit).grade == .s)
    let doubleCrit = try plume(
      [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.critDamage, 5.44)],
      unactivated: Substat(.def, 16.2))
    #expect(try grade(doubleCrit, atkCrit).grade == .a)
    let critAndAtk = try plume(
      [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.atkPercent, 4.08)],
      unactivated: Substat(.def, 16.2))
    #expect(try grade(critAndAtk, atkCrit).grade == .b)
    let oneCrit = try plume(
      [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.def, 16.2)],
      unactivated: Substat(.elementalMastery, 16.32))
    #expect(try grade(oneCrit, atkCrit).grade == .c)
    let junk = try plume(
      [Substat(.hp, 209.13), Substat(.def, 16.2), Substat(.elementalMastery, 16.32)],
      unactivated: Substat(.hpPercent, 4.08))
    #expect(try grade(junk, atkCrit).grade == .d)
    // A four-line start beats the same lines with three, by one upgrade, but at its lowest rolls
    // stays just short of A.
    let fourLine = try plume([
      Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.atkPercent, 4.08),
      Substat(.def, 16.2),
    ])
    let profile = try role(atkCrit).profile
    #expect(
      try Potential.evaluate(fourLine, profile: profile, inventory: [], scope: .offPiece)
        .expectedScore
        > Potential.evaluate(critAndAtk, profile: profile, inventory: [], scope: .offPiece)
        .expectedScore)
    #expect(try grade(fourLine, atkCrit).grade == .b)
  }

  @Test(arguments: [
    (Slot.plume, Stat.atk, "arlecchino.atk-crit"),
    (.flower, .hp, "kuki-shinobu.hyperbloom"),
    (.goblet, .hydroDamage, "furina.off-field-hp"),
    (.sands, .elementalMastery, "alhaitham.spread"),
    (.sands, .energyRecharge, "raiden-shogun.er-crit"),
    (.circlet, .healing, "kokomi.on-field-healer"),
  ])
  func lettersNeedTheirExampleAndAreNoCommonerThanInTheReference(
    slot: Slot, main: Stat, roleID: String
  ) throws {
    let profile = try role(roleID).profile
    let rarity = try DropRarity(slot: slot, main: main, profile: profile)
    let cutoffs = RollGrade.cutoffs(rarity, profile: profile)
    let examples = RollGrade.examples(main: main, profile: profile)
    for ((tier, minimum), ((_, example), (_, share))) in zip(
      cutoffs, zip(examples, RollGrade.shares))
    {
      #expect(minimum >= example, "\(roleID) \(tier)")
      let lowest = rarity.scores.first { Double($0) >= minimum - 1e-6 } ?? rarity.bestScore
      #expect(
        rarity.shareAtOrAbove(lowest) <= share + 1e-12 || lowest == rarity.bestScore,
        "\(roleID) \(tier)")
    }
  }

  @Test func theReferenceBuildIsGradedByItsExamples() throws {
    let rarity = try DropRarity(slot: .plume, main: .atk, profile: RollGrade.reference)
    let cutoffs = RollGrade.cutoffs(rarity, profile: RollGrade.reference)
    #expect(cutoffs.map(\.minimum) == [5287.5, 3100, 2712.5, 1550])
  }

  @Test func oneCritAndEnergyIsNotAnAOnASandsWithFewCoreLines() throws {
    // Alhaitham's EM sands can only roll crit among his core stats.
    let sands = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 0,
      substats: [
        Substat(.critRate, 3.89), Substat(.energyRecharge, 6.48), Substat(.hpPercent, 5.83),
        Substat(.def, 23.15),
      ])
    #expect(try grade(sands, "alhaitham.spread").grade == .b)
    let doubleCrit = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.critDamage, 5.44), Substat(.def, 16.2)],
      unactivated: Substat(.hp, 209.13))
    #expect(try grade(doubleCrit, "alhaitham.spread").grade == .a)
  }

  @Test func singleStatSupportsNeedRollsNotJustTheLine() throws {
    func flower(_ lines: [Substat], level: Int, unactivated: Substat? = nil) throws -> Artifact {
      try Artifact(
        setName: "Test", slot: .flower, main: .hp, level: level, substats: lines,
        unactivated: unactivated)
    }
    let kuki = "kuki-shinobu.hyperbloom"
    // No new EM flower is S for an EM-only role; that needs rolls to land.
    let best = try flower(
      [
        Substat(.elementalMastery, 23.31), Substat(.energyRecharge, 6.48),
        Substat(.hpPercent, 5.83), Substat(.def, 23.15),
      ], level: 0)
    #expect(try grade(best, kuki).grade == .a)
    let three = try flower(
      [
        Substat(.elementalMastery, 69.93), Substat(.atk, 38.9), Substat(.def, 46.3),
        Substat(.energyRecharge, 12.96),
      ], level: 20)
    #expect(try grade(three, kuki).grade == .a)
    let five = try flower(
      [
        Substat(.elementalMastery, 116.55), Substat(.atk, 38.9), Substat(.def, 23.15),
        Substat(.energyRecharge, 6.48),
      ], level: 20)
    #expect(try grade(five, kuki).grade == .s)
  }

  @Test func anUnfinishedPieceIsGradedOnItsExpectedScore() throws {
    let piece = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 16,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 15.54), Substat(.hp, 597.5),
        Substat(.def, 23.15),
      ])
    let summary = try grade(piece, "arlecchino.atk-crit")
    let rarity = try DropRarity(
      slot: .plume, main: .atk, profile: try role("arlecchino.atk-crit").profile)
    let potential = try Potential.evaluate(
      piece, profile: try role("arlecchino.atk-crit").profile, inventory: [], scope: .offPiece)
    #expect(
      summary.grade
        == RollGrade.tier(
          potential.expectedScore * 1000,
          cutoffs: RollGrade.cutoffs(rarity, profile: try role("arlecchino.atk-crit").profile)))
    // Five crit rolls, and half of the last upgrades land on a crit line.
    #expect(summary.grade == .s)
    #expect(summary.chanceOfAOrBetter == 1)
    #expect(summary.p90Share != nil && summary.bestShare != nil)
  }
}
