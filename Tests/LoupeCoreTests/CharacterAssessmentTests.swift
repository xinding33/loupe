import Foundation
import LoupeCore
import Testing

@Suite struct CharacterAssessmentTests {
  private func artifact(
    _ slot: Slot, _ main: Stat, _ stats: [Substat], level: Int = 20,
    set: String = "Test off-piece", rule: RollRule = .ordinary
  ) throws -> Artifact {
    try Artifact(setName: set, slot: slot, main: main, level: level, substats: stats, rule: rule)
  }

  private func match(_ artifact: Artifact, _ id: String) throws -> CharacterMatch {
    try #require(CharacterAssessment.evaluate(artifact).first { $0.characterID == id })
  }

  @Test func strongOffPieceAndOnSetKeepTheSameIntrinsicScreening() throws {
    let stats = [
      Substat(.hpPercent, 17.5), Substat(.critRate, 11.7), Substat(.critDamage, 15.5),
      Substat(.energyRecharge, 6.5),
    ]
    let off = try match(artifact(.goblet, .hydroDamage, stats), "furina")
    let on = try match(artifact(.goblet, .hydroDamage, stats, set: "Golden Troupe"), "furina")
    #expect(off.setFit == .offPiece)
    #expect(on.setFit == .preferred)
    // HP% counts 0.85 and ER 0.25 of a crit roll for Furina.
    #expect(off.potential?.currentScore == 7.8)
    #expect(on.potential?.currentScore == off.potential?.currentScore)
    #expect(on.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
    #expect(off.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
    #expect(on.grades?.grade == off.grades?.grade)
  }

  @Test func alternativeSetRetainsItsTeamCondition() throws {
    let piece = try artifact(
      .goblet, .hydroDamage,
      [
        Substat(.hpPercent, 17.5), Substat(.critRate, 11.7), Substat(.critDamage, 15.5),
        Substat(.energyRecharge, 6.5),
      ], set: "Tenacity of the Millelith")
    let result = try match(piece, "furina")
    #expect(result.setFit == .alternative)
    #expect(
      result.conditions.contains { $0.kind == .setActivation && $0.explanation.contains("ATK") })
  }

  @Test func reviewedIncludesUnownedDistinctCharactersWithoutRawScoreRanking() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 140), Substat(.atk, 19), Substat(.def, 23),
        Substat(.hpPercent, 5.8),
      ])
    let results = CharacterAssessment.evaluate(piece, roles: CharacterRoles.reviewed)
    #expect(
      results.map(\.characterID) == [
        "alhaitham", "bennett", "fischl", "furina", "itto", "kazuha", "kokomi", "kuki-shinobu",
        "nahida", "neuvillette", "raiden-shogun", "sucrose", "xiangling", "xingqiu", "yelan",
      ])
    #expect(
      results.filter {
        ["furina", "itto", "kokomi", "kuki-shinobu", "xiangling"].contains($0.characterID)
      }
      .map(\.characterID) == ["furina", "itto", "kokomi", "kuki-shinobu", "xiangling"])
    #expect(Set(results.map(\.id)).count == results.count)
    #expect(try match(piece, "kuki-shinobu").potential?.currentScore == 6.25)
    #expect(CharacterAssessment.coverageDescription.contains("15 roles were reviewed one by one"))
  }

  @Test func wrongMainDoesNotProduceSpeculativeUsers() throws {
    let stats = [
      Substat(.defPercent, 21.9), Substat(.critRate, 11.7), Substat(.critDamage, 15.5),
      Substat(.energyRecharge, 6.5),
    ]
    let geo = try artifact(.goblet, .geoDamage, stats)
    #expect(
      CharacterAssessment.evaluate(geo, roles: CharacterRoles.reviewed).map(\.characterID) == [
        "itto"
      ])
    let physical = try artifact(.goblet, .physicalDamage, stats)
    #expect(CharacterAssessment.evaluate(physical, roles: CharacterRoles.reviewed).isEmpty)
    // Archetype roles take a DMG Bonus goblet only for the character's own damage type.
    #expect(
      Set(CharacterAssessment.evaluate(physical).map(\.characterID)) == [
        "eula", "freminet", "razor", "xinyan",
      ])
    #expect(
      CharacterAssessment.evaluate(geo).allSatisfy { $0.role.mains[.goblet]!.contains(.geoDamage) })
    #expect(CharacterRoles.noMatchDescription.contains("No character role"))
  }

  @Test func kokomiCritRollsDoNotIncreaseHealingScreen() throws {
    let before = try artifact(
      .circlet, .healing,
      [
        Substat(.critRate, 15.6), Substat(.critDamage, 15.5), Substat(.atk, 19), Substat(.def, 23),
      ], level: 16)
    let after = try artifact(
      .circlet, .healing,
      [
        Substat(.critRate, 19.5), Substat(.critDamage, 15.5), Substat(.atk, 19), Substat(.def, 23),
      ])
    let initial = try match(before, "kokomi")
    let final = try match(after, "kokomi")
    #expect(initial.potential?.currentScore == 0)
    #expect(final.potential?.currentScore == 0)
    #expect(final.profile.weights[.critRate, default: 0] == 0)
    #expect(final.profile.weights[.critDamage, default: 0] == 0)
    #expect(final.grades?.grade == .d)
    #expect(final.grades?.rarityShare == initial.grades?.rarityShare)
    #expect(final.reasons.contains { $0.contains("not a strong match") })
    #expect(final.conditions.contains { $0.explanation.contains("Crit Rate penalty") })
  }

  @Test func energyContributionNeverClaimsThatAnUnknownBuildMeetsItsRequirement() throws {
    let piece = try artifact(
      .goblet, .hydroDamage,
      [
        Substat(.energyRecharge, 38.9), Substat(.hpPercent, 5.8), Substat(.atk, 19),
        Substat(.def, 23),
      ])
    let result = try match(piece, "furina")
    // Six ER rolls count a quarter each, below one HP% roll and a half.
    #expect(result.potential?.currentScore == 2.35)
    #expect(result.secondaryStats.contains(.energyRecharge))
    #expect(result.conditions.contains { $0.kind == .energy && $0.status == .unknown })
    #expect(result.conditions.contains { $0.kind == .critBalance && $0.status == .unknown })
    #expect(result.profile.weights[.energyRecharge] == RollWeights.secondary)
  }

  @Test func specialRollRulesRetainRoleExplanationsWithoutInventedOdds() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 140), Substat(.atk, 19), Substat(.def, 23),
        Substat(.hpPercent, 5.8),
      ], rule: .special)
    let result = try match(piece, "kuki-shinobu")
    #expect(result.potential == nil)
    #expect(result.potentialUnavailableReason?.contains("ordinary") == true)
    #expect(!result.reasons.isEmpty)
  }

  @Test func inventoryOnlyChangesComparisonsAndExcludesLinkedCandidate() throws {
    let candidate = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 140), Substat(.atk, 19), Substat(.def, 23),
        Substat(.hpPercent, 5.8),
      ])
    let linked = try candidate.withID(UUID())
    let duplicate = try candidate.withID(UUID())
    let empty = try match(candidate, "kuki-shinobu")
    let populated = try #require(
      CharacterAssessment.evaluate(
        candidate, inventory: [linked, duplicate], scope: .offPiece, excluding: linked.id
      ).first { $0.characterID == "kuki-shinobu" })
    #expect(populated.potential?.comparisonCount == 1)
    #expect(populated.potential?.chanceToBeatBest == 0)
    #expect(populated.potential?.rankChances.first?.probability == 1)
    #expect(populated.potential?.distribution == empty.potential?.distribution)
    #expect(populated.grades?.grade == empty.grades?.grade)
    #expect(empty.potential?.chanceToBeatBest == nil)
  }

  @Test func unfinishedGradeUsesTheExpectedScoreAndUsefulUpgradeIsMonotone() throws {
    let before = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 93.24), Substat(.atk, 38.90), Substat(.def, 23.15),
        Substat(.hpPercent, 5.83),
      ], level: 16)
    let final = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 116.55), Substat(.atk, 38.90), Substat(.def, 23.15),
        Substat(.hpPercent, 5.83),
      ])
    let initial = try match(before, "kuki-shinobu")
    #expect(initial.grades?.grade == .s)
    #expect(initial.grades?.chanceOfAOrBetter == 1)
    #expect(try match(final, "kuki-shinobu").grades?.grade == .s)
    let upgraded = try before.upgraded(to: final)
    #expect(upgraded.substats == final.substats)
  }

  @Test func aOrBetterProbabilityUsesTheWholeDistribution() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 23.31), Substat(.atk, 58.35), Substat(.def, 69.45),
        Substat(.hpPercent, 5.83),
      ], level: 16)
    let result = try match(piece, "kuki-shinobu")
    #expect(result.potential?.currentScore == 1.25)
    #expect(result.grades?.grade == .d)
    // A needs more than 2.05: only an EM roll of tier 9 or 10 gets there.
    #expect(result.grades?.chanceOfAOrBetter == 2.0 / 16)
  }

  @Test(arguments: [Slot.sands, .goblet, .circlet])
  func emMainIsUsefulButHasNoScalarComparison(slot: Slot) throws {
    let piece = try artifact(
      slot, .elementalMastery,
      [
        Substat(.atk, 116.7), Substat(.def, 23.15), Substat(.hpPercent, 5.83),
        Substat(.critRate, 3.89),
      ])
    let copies = try [piece.withID(UUID()), piece.withID(UUID()), piece.withID(UUID())]
    let result = try #require(
      CharacterAssessment.evaluate(piece, inventory: copies).first {
        $0.characterID == "kuki-shinobu"
      })
    #expect(result.grades == nil)
    #expect(result.potential == nil)
    #expect(result.potentialUnavailableReason?.contains("no eligible core substats") == true)
    #expect(result.reasons.contains { $0.contains("EM substat is impossible") })
    #expect(throws: ArtifactError.self) {
      try artifact(
        .goblet, .elementalMastery,
        [
          Substat(.elementalMastery, 139.86), Substat(.def, 23.15), Substat(.hpPercent, 5.83),
          Substat(.critRate, 3.89),
        ])
    }
  }

  @Test func absentEmOnFlowerStillHasAValidZeroScoreAndComparison() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.atk, 97.25), Substat(.def, 46.30), Substat(.hpPercent, 5.83),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try #require(
      CharacterAssessment.evaluate(
        piece, inventory: [piece.withID(UUID())]
      ).first { $0.characterID == "kuki-shinobu" })
    // HP% and ER count a quarter roll each for Kuki; no EM line means D.
    #expect(result.potential?.distribution == [500: 1])
    #expect(result.potential?.comparisonCount == 1)
    #expect(result.potential?.rankChances.first?.probability == 1)
    #expect(result.potentialUnavailableReason == nil)
    #expect(result.grades?.grade == .d)
  }

  @Test func hpMainAlsoRemovesKokomisOnlyCoreSubstat() throws {
    let piece = try artifact(
      .sands, .hpPercent,
      [
        Substat(.atk, 97.25), Substat(.def, 46.30), Substat(.hp, 298.75),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try match(piece, "kokomi")
    #expect(result.potential == nil)
    #expect(result.potentialUnavailableReason?.contains("no eligible core substats") == true)
  }

  @Test func missingFourthKeepsMatchesButDoesNotInventProjectionOrGrades() throws {
    let piece = try artifact(
      .goblet, .hydroDamage,
      [
        Substat(.hpPercent, 5.83), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
      ], level: 0)
    let result = try match(piece, "furina")
    #expect(result.potential == nil)
    #expect(result.potentialUnavailableReason != nil)
    #expect(result.grades?.grade == nil)
    #expect(result.grades?.grade == nil)
    #expect(result.grades?.chanceOfAOrBetter == nil)
  }

  @Test func cancellationSkipsRoleComputations() async throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 140), Substat(.atk, 19), Substat(.def, 23),
        Substat(.hpPercent, 5.8),
      ])
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return CharacterAssessment.evaluate(piece)
    }
    #expect(await task.value.isEmpty)
  }

  @Test func reactionAndErMainAssumptionsStayVisibleBesideTheRoleGrade() throws {
    let piece = try artifact(
      .sands, .energyRecharge,
      [
        Substat(.elementalMastery, 139.86), Substat(.atkPercent, 5.83),
        Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
      ])
    let result = try match(piece, "xiangling")
    #expect(result.grades?.calibrationID.hasPrefix(RollGrade.version) == true)
    #expect(result.conditions.contains { $0.kind == .team && $0.status == .unknown })
    #expect(result.conditions.contains { $0.kind == .mainStat && $0.status == .unknown })
    #expect(result.profile.weights[.elementalMastery] == RollWeights.atkLike)
    #expect(!CharacterAssessment.evaluate(piece).contains { $0.characterID == "kuki-shinobu" })
  }

  @Test(arguments: [
    ("furina", Slot.goblet, Stat.hydroDamage, Stat.hpPercent, 23.32, 7.78, 7.77),
    ("furina", .goblet, .hydroDamage, .hpPercent, 17.49, 11.67, 7.77),
    ("furina", .goblet, .hydroDamage, .hpPercent, 17.49, 7.78, 15.54),
    ("itto", .goblet, .geoDamage, .defPercent, 29.16, 7.78, 7.77),
    ("itto", .goblet, .geoDamage, .defPercent, 21.87, 11.67, 7.77),
    ("itto", .goblet, .geoDamage, .defPercent, 21.87, 7.78, 15.54),
  ])
  func addingAnyCoreRollToALegalFinishedArtifactNeverLowersQuality(
    id: String, slot: Slot, main: Stat, scaling: Stat, value: Double, cr: Double, cd: Double
  ) throws {
    let base = try artifact(
      slot, main,
      [
        Substat(scaling, scaling == .hpPercent ? 17.49 : 21.87), Substat(.critRate, 7.78),
        Substat(.critDamage, 7.77), Substat(.atk, 38.90),
      ])
    let improved = try artifact(
      slot, main,
      [
        Substat(scaling, value), Substat(.critRate, cr), Substat(.critDamage, cd),
        Substat(.atk, 38.90),
      ])
    let tiers = ArtifactTier.allCases
    let before = try #require(try match(base, id).grades?.grade)
    let after = try #require(try match(improved, id).grades?.grade)
    #expect(tiers.firstIndex(of: after)! <= tiers.firstIndex(of: before)!)
    #expect(
      try match(improved, id).potential!.currentScore > match(base, id).potential!.currentScore)
  }
}
