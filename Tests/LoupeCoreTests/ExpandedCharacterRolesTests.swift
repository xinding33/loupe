import Foundation
import LoupeCore
import Testing

@Suite struct ExpandedCharacterRolesTests {
  private func match(
    _ piece: Artifact, _ id: String, inventory: [Artifact] = [],
    scope: ComparisonScope = .offPiece, excluding: UUID? = nil
  ) throws -> CharacterMatch {
    try #require(
      CharacterAssessment.evaluate(piece, inventory: inventory, scope: scope, excluding: excluding)
        .first { $0.characterID == id })
  }

  private func flower(set: String = "Test off-piece") throws -> Artifact {
    try Artifact(
      setName: set, slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.elementalMastery, 139.86), Substat(.atk, 19.45), Substat(.def, 23.15),
        Substat(.hpPercent, 5.83),
      ])
  }

  @Test func reviewedRegistryIsDistinctCompleteAndHasLegalSourcedRoles() throws {
    let results = CharacterAssessment.evaluate(try flower(), roles: CharacterRoles.reviewed)
    #expect(
      results.map(\.characterID) == [
        "alhaitham", "bennett", "fischl", "furina", "itto", "kazuha", "kokomi", "kuki-shinobu",
        "nahida", "neuvillette", "raiden-shogun", "sucrose", "xiangling", "xingqiu", "yelan",
      ])
    #expect(Set(results.map(\.characterID)).count == 15)
    #expect(Set(results.map(\.roleID)).count == 15)
    #expect(CharacterRoles.reviewed.map(\.roleID) == results.map(\.roleID))
    #expect(
      CharacterRoles.pilot.map(\.characterID).sorted() == [
        "furina", "itto", "kokomi", "kuki-shinobu", "xiangling",
      ])
    for result in results {
      #expect(!result.profile.weights.isEmpty)
      // Core stats weigh a full or discounted roll; secondary stats a quarter.
      #expect(
        result.profile.weights.values.allSatisfy {
          [RollWeights.secondary, RollWeights.atkLike, RollWeights.hpLike, 100].contains($0)
        })
      #expect(
        result.secondaryStats.allSatisfy {
          result.profile.weights[$0] == RollWeights.secondary
        })
      #expect(Set(result.usefulStats).isDisjoint(with: result.secondaryStats))
      #expect(result.conditions.allSatisfy { $0.status == .unknown })
      #expect(result.role.source.url.hasPrefix("https://"))
      #expect(!result.role.source.section.isEmpty)
      #expect(!result.role.source.sourceVersion.isEmpty)
      #expect(!result.role.source.reviewedOn.isEmpty)
      for slot in Slot.allCases {
        let mains = try #require(result.role.mains[slot])
        #expect(!mains.isEmpty)
        #expect(mains.allSatisfy { slot.mainStats.contains($0) })
      }
    }
  }

  @Test(arguments: [
    ("alhaitham", Stat.elementalMastery), ("bennett", .energyRecharge),
    ("fischl", .atkPercent), ("kazuha", .elementalMastery), ("nahida", .elementalMastery),
    ("neuvillette", .hpPercent), ("raiden-shogun", .elementalMastery),
    ("sucrose", .elementalMastery), ("xingqiu", .atkPercent), ("yelan", .hpPercent),
  ])
  func eachNewRoleAcceptsAReviewedMainAndRejectsAWrongMain(id: String, main: Stat) throws {
    let stats = [
      Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.critRate, 3.89),
      Substat(.critDamage, 7.77),
    ]
    let eligible = try Artifact(
      setName: "Test off-piece", slot: .sands, main: main, level: 0, substats: stats)
    let wrong = try Artifact(
      setName: "Test off-piece", slot: .sands, main: .defPercent, level: 0, substats: stats)
    let result = try match(eligible, id)
    #expect(result.setFit == .offPiece)
    // Graded unless the role's core stats cannot appear as substats on this main.
    #expect((result.grades == nil) == !result.usefulStats.contains { $0 != main })
    #expect(!CharacterAssessment.evaluate(wrong).contains { $0.characterID == id })
  }

  @Test(arguments: [
    ("alhaitham", "Gilded Dreams"), ("bennett", "Noblesse Oblige"),
    ("fischl", "Golden Troupe"), ("kazuha", "Viridescent Venerer"),
    ("nahida", "Deepwood Memories"), ("neuvillette", "Marechaussee Hunter"),
    ("raiden-shogun", "Flower of Paradise Lost"), ("sucrose", "Viridescent Venerer"),
    ("xingqiu", "Emblem of Severed Fate"), ("yelan", "Emblem of Severed Fate"),
  ])
  func preferredSetsDoNotSuppressOffPiecesOrChangeCoreScores(id: String, set: String) throws {
    let on = try match(flower(set: set), id)
    let off = try match(flower(), id)
    #expect(on.setFit == .preferred)
    #expect(off.setFit == .offPiece)
    #expect(on.potential?.distribution == off.potential?.distribution)
    #expect(on.grades?.grade != nil)
    #expect(on.grades?.grade == off.grades?.grade)
    #expect(on.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
    #expect(off.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
  }

  @Test(arguments: [
    ("alhaitham", "Deepwood Memories"), ("bennett", "Scroll of the Hero of Cinder City"),
    ("fischl", "Gilded Dreams"), ("nahida", "Gilded Dreams"),
    ("neuvillette", "Heart of Depth"), ("raiden-shogun", "Gilded Dreams"),
    ("sucrose", "Deepwood Memories"), ("xingqiu", "Noblesse Oblige"),
    ("yelan", "Nymph's Dream"),
  ])
  func alternativesRetainActivationConditionsWithoutNumericalSetBonuses(
    id: String, set: String
  ) throws {
    let alternative = try match(flower(set: set), id)
    let off = try match(flower(), id)
    #expect(alternative.setFit == .alternative)
    #expect(alternative.potential?.currentScore == off.potential?.currentScore)
    #expect(alternative.conditions.contains { $0.kind == .setActivation && $0.status == .unknown })
  }

  @Test(arguments: ["kazuha", "raiden-shogun", "sucrose"], [Slot.sands, .goblet, .circlet])
  func emMainCannotInventScalarRanksEvenWithSavedCopies(id: String, slot: Slot) throws {
    let piece = try Artifact(
      setName: "Test off-piece", slot: slot, main: .elementalMastery, level: 20,
      substats: [
        Substat(.atk, 116.70), Substat(.def, 23.15), Substat(.critRate, 3.89),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try match(piece, id, inventory: [piece.withID(UUID())])
    #expect(result.potential == nil)
    #expect(result.grades == nil)
    #expect(result.potentialUnavailableReason?.contains("no eligible core substats") == true)
    #expect(result.reasons.contains { $0.contains("EM substat is impossible") })
  }

  @Test(arguments: [Slot.sands, .goblet, .circlet])
  func bennettHpMainHasNoScalarRanks(slot: Slot) throws {
    let piece = try Artifact(
      setName: "Noblesse Oblige", slot: slot, main: .hpPercent, level: 20,
      substats: [
        Substat(.atk, 116.70), Substat(.def, 23.15), Substat(.hp, 298.75),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try match(piece, "bennett", inventory: [piece.withID(UUID())])
    #expect(result.potential == nil)
    #expect(result.grades == nil)
    #expect(result.potentialUnavailableReason?.contains("no eligible core substats") == true)
  }

  @Test(arguments: ["kazuha", "raiden-shogun", "sucrose"])
  func emOnlyRolesCountCritOnlyAsASecondaryStat(id: String) throws {
    let before = try Artifact(
      setName: "Test off-piece", slot: .flower, main: .hp, level: 16,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.atk, 19.45), Substat(.def, 23.15),
        Substat(.critRate, 15.56),
      ])
    let after = try Artifact(
      setName: "Test off-piece", slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.atk, 19.45), Substat(.def, 23.15),
        Substat(.critRate, 19.45),
      ])
    let initial = try match(before, id)
    let final = try match(after, id)
    // Kazuha and Sucrose list CRIT Rate for Favonius: a quarter roll. Raiden's Hyperbloom does not.
    let quarter = Double(final.profile.weights[.critRate, default: 0]) / 100
    #expect(quarter <= Double(RollWeights.secondary) / 100)
    #expect(initial.potential?.currentScore == 1 + 4 * quarter)
    #expect(final.potential?.currentScore == 1 + 5 * quarter)
    #expect(final.profile.weights[.critDamage, default: 0] == 0)
  }

  @Test func bennettArtifactAttackCannotImproveTheBuffScreen() throws {
    let before = try Artifact(
      setName: "Noblesse Oblige", slot: .circlet, main: .healing, level: 16,
      substats: [
        Substat(.hpPercent, 5.83), Substat(.atkPercent, 23.32), Substat(.critRate, 3.89),
        Substat(.atk, 19.45),
      ])
    let after = try Artifact(
      setName: "Noblesse Oblige", slot: .circlet, main: .healing, level: 20,
      substats: [
        Substat(.hpPercent, 5.83), Substat(.atkPercent, 29.15), Substat(.critRate, 3.89),
        Substat(.atk, 19.45),
      ])
    let initial = try match(before, "bennett")
    let final = try match(after, "bennett")
    // One HP% roll and a quarter-weight CRIT Rate roll; ATK never counts.
    #expect(initial.potential?.currentScore == 1.25)
    #expect(final.potential?.currentScore == 1.25)
    #expect(final.profile.weights[.atkPercent, default: 0] == 0)
    #expect(final.profile.weights[.atk, default: 0] == 0)
    #expect(final.profile.weights[.critRate] == RollWeights.secondary)
    #expect(final.grades?.rarityShare == initial.grades?.rarityShare)
    #expect(final.conditions.contains { $0.explanation.contains("base ATK") })
  }

  @Test(arguments: ["kazuha", "raiden-shogun", "sucrose", "bennett"])
  func absentCoreOnAnEligibleSlotIsAValidZeroNotAMissingProfile(id: String) throws {
    let piece = try Artifact(
      setName: "Test off-piece", slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.atk, 116.70), Substat(.def, 23.15), Substat(.critRate, 3.89),
        Substat(.energyRecharge, 6.48),
      ])
    let result = try match(piece, id)
    // Only secondary stats can score here.
    #expect(result.potential?.distribution == [result.profile.score(piece.substats): 1])
    #expect(result.profile.score(piece.substats) <= 500)
    #expect(result.potential?.comparisonCount == 0)
    #expect(result.potential?.rankChances.isEmpty == true)
    #expect(result.potential?.chanceToBeatBest == nil)
    #expect(result.potentialUnavailableReason == nil)
    #expect(result.grades?.grade == .d)
  }

  @Test func conditionsDoNotTurnReactionOrErAssumptionsIntoKnownBuildFacts() throws {
    let piece = try flower()
    let nahida = try match(piece, "nahida")
    let fischl = try match(piece, "fischl")
    let raiden = try match(piece, "raiden-shogun")
    #expect(
      nahida.potential?.currentScore == 6 * Double(nahida.profile.weights[.elementalMastery]!) / 100
    )
    #expect(nahida.conditions.contains { $0.explanation.contains("passive caps") })
    #expect(nahida.conditions.contains { $0.explanation.contains("not assumed to own Hyperbloom") })
    #expect(fischl.conditions.contains { $0.kind == .team && $0.explanation.contains("Aggravate") })
    #expect(raiden.profile.weights[.energyRecharge, default: 0] == 0)
    #expect(raiden.conditions.contains { $0.explanation.contains("does not need Burst ER") })
    let er = try Artifact(
      setName: "Viridescent Venerer", slot: .sands, main: .energyRecharge, level: 20,
      substats: [
        Substat(.elementalMastery, 139.86), Substat(.atk, 19.45), Substat(.def, 23.15),
        Substat(.critRate, 3.89),
      ])
    let kazuha = try match(er, "kazuha")
    // Six EM rolls and a quarter-weight CRIT Rate roll.
    #expect(kazuha.potential?.currentScore == 6.25)
    #expect(kazuha.conditions.contains { $0.kind == .mainStat && $0.status == .unknown })
    #expect(kazuha.conditions.contains { $0.explanation.contains("Favonius") })
    #expect(!CharacterAssessment.evaluate(er).contains { $0.characterID == "sucrose" })
    // Only Raiden's archetype Burst role takes an ER sands; her reviewed Hyperbloom role does not.
    #expect(
      CharacterAssessment.evaluate(er).filter { $0.characterID == "raiden-shogun" }.map(\.roleID)
        == ["raiden-shogun.er-crit"])
  }

  @Test(arguments: ["kazuha", "sucrose", "bennett", "raiden-shogun"])
  func favoniusDoesNotMakeCritCircletsStandardSupportMains(id: String) throws {
    let piece = try Artifact(
      setName: "Test off-piece", slot: .circlet, main: .critRate, level: 0,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.hpPercent, 5.83),
        Substat(.energyRecharge, 6.48), Substat(.def, 23.15),
      ])
    #expect(
      !CharacterAssessment.evaluate(piece, roles: CharacterRoles.reviewed).contains {
        $0.characterID == id
      })
  }

  @Test func expandedRolesKeepSavedScopeAndActualVersusForecastSemantics() throws {
    let candidate = try flower(set: "Viridescent Venerer")
    let linked = try candidate.withID(UUID())
    let duplicate = try candidate.withID(UUID())
    let otherSet = try flower()
    let saved = [linked, duplicate, otherSet]
    let same = try match(
      candidate, "kazuha", inventory: saved, scope: .sameSet, excluding: linked.id)
    let all = try match(candidate, "kazuha", inventory: saved, excluding: linked.id)
    #expect(same.potential?.comparisonCount == 1)
    #expect(all.potential?.comparisonCount == 2)
    #expect(all.potential?.distribution == [6000: 1])
    #expect(all.potential?.summary.p50Score == 6)
    #expect(all.potential?.summary.p90Score == 6)
    #expect(all.potential?.summary.bestPossibleScore == 6)
    #expect(all.potential?.chanceToBeatBest == 0)
    let unfinished = try Artifact(
      setName: "Viridescent Venerer", slot: .flower, main: .hp, level: 16,
      substats: [
        Substat(.elementalMastery, 62.95), Substat(.atk, 58.35), Substat(.def, 23.15),
        Substat(.hpPercent, 5.83),
      ])
    let forecast = try match(unfinished, "kazuha")
    #expect(forecast.potential?.currentScore == 2.7)
    #expect(forecast.potential?.summary.p50Score == 2.7)
    #expect(forecast.potential?.summary.p90Score == 3.6)
    #expect(forecast.potential?.summary.bestPossibleScore == 3.7)
    #expect(forecast.grades?.grade != nil)
  }

  @Test(arguments: ["neuvillette", "yelan", "xingqiu"])
  func incompleteOrSpecialArtifactsKeepMatchesWithoutInventedOdds(id: String) throws {
    let stats = [Substat(.hpPercent, 5.83), Substat(.critRate, 3.89), Substat(.critDamage, 7.77)]
    let unknownFourth = try Artifact(
      setName: "Test off-piece", slot: .goblet, main: .hydroDamage, level: 0, substats: stats)
    let special = try Artifact(
      setName: "Test off-piece", slot: .goblet, main: .hydroDamage, level: 0,
      substats: stats + [Substat(.atk, 19.45)], rule: .special)
    let incomplete = try match(unknownFourth, id)
    let unsupported = try match(special, id)
    #expect(incomplete.potential == nil)
    #expect(incomplete.potentialUnavailableReason?.contains("fourth stat") == true)
    #expect(unsupported.potential == nil)
    #expect(unsupported.potentialUnavailableReason?.contains("ordinary") == true)
    #expect(incomplete.grades == nil)
    #expect(unsupported.grades == nil)
  }

  @Test(arguments: [
    ("furina", 0.85), ("itto", 0.0), ("kokomi", 1.0), ("kuki-shinobu", 6.25), ("xiangling", 4.5),
  ])
  func originalFiveRetainTheirCoreScreensAndRoles(id: String, score: Double) throws {
    let result = try match(flower(), id)
    let original = try #require(CharacterRoles.pilot.first { $0.characterID == id })
    #expect(result.roleID == original.roleID)
    #expect(result.profile.weights == original.profile.weights)
    #expect(result.potential?.currentScore == score)
  }
}
