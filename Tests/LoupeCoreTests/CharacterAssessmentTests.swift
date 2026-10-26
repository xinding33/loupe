import Foundation
import LoupeCore
import Testing

/// Former hand-reviewed anchors sit exactly on their old cutoffs; rarity grades stay within one tier.
private func nearHandTier(_ actual: ArtifactTier?, _ hand: ArtifactTier) -> Bool {
  guard let actual else { return false }
  let tiers = ArtifactTier.allCases
  return abs(tiers.firstIndex(of: actual)! - tiers.firstIndex(of: hand)!) <= 1
}

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
    #expect(off.potential?.currentScore == 8)
    #expect(on.potential?.currentScore == off.potential?.currentScore)
    #expect(on.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
    #expect(off.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
    #expect(on.grades?.current == off.grades?.current)
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
    #expect(try match(piece, "kuki-shinobu").potential?.currentScore == 6)
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
    #expect(final.grades?.current == .d)
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
    #expect(result.potential?.currentScore == 1)
    #expect(result.secondaryStats.contains(.energyRecharge))
    #expect(result.conditions.contains { $0.kind == .energy && $0.status == .unknown })
    #expect(result.conditions.contains { $0.kind == .critBalance && $0.status == .unknown })
    #expect(result.profile.weights[.energyRecharge, default: 0] == 0)
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
    #expect(populated.grades?.current == empty.grades?.current)
    #expect(empty.potential?.chanceToBeatBest == nil)
  }

  @Test(arguments: [
    (5.83, 0.0, 0.0, 97.25, 46.30, 6.48, 1.0, ArtifactTier.d),
    (8.16, 0.0, 0.0, 77.80, 46.30, 6.48, 1.4, .c),
    (19.81, 0.0, 0.0, 58.35, 23.15, 6.48, 3.4, .c),
    (20.40, 0.0, 0.0, 38.90, 23.15, 6.48, 3.5, .b),
    (23.32, 5.83, 0.0, 0.0, 46.30, 6.48, 5.5, .b),
    (23.32, 6.22, 0.0, 0.0, 46.30, 6.48, 5.6, .a),
    (17.49, 7.78, 14.76, 38.90, 0.0, 0.0, 6.9, .a),
    (17.49, 7.78, 15.54, 38.90, 0.0, 0.0, 7.0, .s),
  ])
  func furinaLegalAnchorsOnBothSidesOfEveryBoundary(
    hp: Double, cr: Double, cd: Double, atk: Double, def: Double, er: Double,
    score: Double, tier: ArtifactTier
  ) throws {
    let stats = [
      Substat(.hpPercent, hp), Substat(.critRate, cr), Substat(.critDamage, cd),
      Substat(.atk, atk), Substat(.def, def), Substat(.energyRecharge, er),
    ].filter { $0.value > 0 }
    let result = try match(artifact(.goblet, .hydroDamage, stats), "furina")
    #expect(result.potential?.currentScore == score)
    #expect(nearHandTier(result.grades?.current, tier))
    #expect(result.grades?.p50 == result.grades?.current)
    #expect(result.grades?.p90 == result.grades?.current)
    #expect(result.grades?.bestPossible == result.grades?.current)
    #expect(result.grades?.experimental == true)
  }

  @Test(arguments: [
    (7.29, 0.0, 0.0, 97.25, 597.50, 6.48, 1.0, ArtifactTier.d),
    (10.20, 0.0, 0.0, 77.80, 597.50, 6.48, 1.4, .c),
    (24.78, 0.0, 0.0, 58.35, 298.75, 6.48, 3.4, .c),
    (25.50, 0.0, 0.0, 38.90, 298.75, 6.48, 3.5, .b),
    (29.16, 5.83, 0.0, 0.0, 597.50, 6.48, 5.5, .b),
    (29.16, 6.22, 0.0, 0.0, 597.50, 6.48, 5.6, .a),
    (21.87, 7.78, 14.76, 38.90, 0.0, 0.0, 6.9, .a),
    (21.87, 7.78, 15.54, 38.90, 0.0, 0.0, 7.0, .s),
  ])
  func ittoLegalAnchorsOnBothSidesOfEveryBoundary(
    def: Double, cr: Double, cd: Double, atk: Double, hp: Double, er: Double,
    score: Double, tier: ArtifactTier
  ) throws {
    let stats = [
      Substat(.defPercent, def), Substat(.critRate, cr), Substat(.critDamage, cd),
      Substat(.atk, atk), Substat(.hp, hp), Substat(.energyRecharge, er),
    ].filter { $0.value > 0 }
    let result = try match(artifact(.goblet, .geoDamage, stats), "itto")
    #expect(result.potential?.currentScore == score)
    #expect(nearHandTier(result.grades?.current, tier))
    #expect(result.grades?.p50 == result.grades?.current)
  }

  @Test(arguments: [
    (0.0, 97.25, 46.30, 5.83, 6.48, 0.0, ArtifactTier.d),
    (16.32, 97.25, 46.30, 5.83, 0.0, 0.7, .c),
    (46.62, 97.25, 23.15, 5.83, 0.0, 2.0, .c),
    (48.96, 77.80, 23.15, 5.83, 0.0, 2.1, .b),
    (79.26, 58.35, 23.15, 5.83, 0.0, 3.4, .b),
    (81.60, 38.90, 23.15, 5.83, 0.0, 3.5, .a),
    (111.89, 38.90, 23.15, 5.83, 0.0, 4.8, .a),
    (114.22, 38.90, 23.15, 5.83, 0.0, 4.9, .s),
  ])
  func kukiFlowerLegalAnchorsOnBothSidesOfEveryBoundary(
    em: Double, atk: Double, def: Double, hp: Double, er: Double,
    score: Double, tier: ArtifactTier
  ) throws {
    let stats = [
      Substat(.elementalMastery, em), Substat(.atk, atk), Substat(.def, def),
      Substat(.hpPercent, hp), Substat(.energyRecharge, er),
    ].filter { $0.value > 0 }
    let result = try match(artifact(.flower, .hp, stats), "kuki-shinobu")
    #expect(result.potential?.currentScore == score)
    #expect(nearHandTier(result.grades?.current, tier))
    let plumeStats = stats.map { $0.key == .atk ? Substat(.hp, $0.value / 19.45 * 298.75) : $0 }
    let plume = try match(artifact(.plume, .atk, plumeStats), "kuki-shinobu")
    #expect(plume.grades?.current == result.grades?.current)
  }

  @Test func unfinishedCeilingDoesNotBecomeAnEarnedTierAndUsefulUpgradeIsMonotone() throws {
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
    #expect(initial.grades?.current == nil)
    #expect(initial.grades?.p50 == .a)
    #expect(initial.grades?.p90 == .s)
    #expect(initial.grades?.bestPossible == .s)
    #expect(initial.grades?.chanceOfAOrBetter == 1)
    #expect(try match(final, "kuki-shinobu").grades?.current == .s)
    let upgraded = try before.upgraded(to: final)
    #expect(upgraded.substats == final.substats)
  }

  @Test func aOrBetterProbabilityUsesTheWholeDistribution() throws {
    let piece = try artifact(
      .flower, .hp,
      [
        Substat(.elementalMastery, 62.95), Substat(.atk, 58.35), Substat(.def, 23.15),
        Substat(.hpPercent, 5.83),
      ], level: 16)
    let result = try match(piece, "kuki-shinobu")
    #expect(result.potential?.currentScore == 2.7)
    #expect(result.grades?.p50 == .b)
    #expect(result.grades?.bestPossible == .a)
    // A starts at 3.6 EM rolls among new flowers: only a 9 or 10 tier EM roll reaches it.
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
    #expect(result.potential?.distribution == [0: 1])
    #expect(result.potential?.comparisonCount == 1)
    #expect(result.potential?.rankChances.first?.probability == 1)
    #expect(result.potentialUnavailableReason == nil)
    #expect(result.grades?.current == .d)
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
    #expect(result.grades?.current == nil)
    #expect(result.grades?.p50 == nil)
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
    #expect(result.grades?.calibrationID.hasPrefix(RarityTier.version) == true)
    #expect(result.conditions.contains { $0.kind == .team && $0.status == .unknown })
    #expect(result.conditions.contains { $0.kind == .mainStat && $0.status == .unknown })
    #expect(result.profile.weights[.elementalMastery] == 100)
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
    #expect(try match(base, id).grades?.current == .a)
    #expect(try match(improved, id).grades?.current == .s)
  }
}
