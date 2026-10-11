import ArtifactCore
import Foundation
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
    let results = CharacterAssessment.evaluate(try flower())
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
      #expect(result.profile.weights.values.allSatisfy { $0 == 100 })
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
    #expect(result.grades == nil)
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
    #expect(on.grades == nil)
    #expect(off.grades == nil)
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
  func emOnlyRolesDoNotRewardCritRolls(id: String) throws {
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
    #expect(initial.potential?.currentScore == 1)
    #expect(final.potential?.currentScore == 1)
    #expect(final.profile.weights[.critRate, default: 0] == 0)
    #expect(final.profile.weights[.critDamage, default: 0] == 0)
    #expect(final.grades == nil)
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
    #expect(initial.potential?.currentScore == 1)
    #expect(final.potential?.currentScore == 1)
    #expect(final.profile.weights[.atkPercent, default: 0] == 0)
    #expect(final.profile.weights[.atk, default: 0] == 0)
    #expect(final.profile.weights[.critRate, default: 0] == 0)
    #expect(final.grades == nil)
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
    #expect(result.potential?.distribution == [0: 1])
    #expect(result.potential?.comparisonCount == 0)
    #expect(result.potential?.rankChances.isEmpty == true)
    #expect(result.potential?.chanceToBeatBest == nil)
    #expect(result.potentialUnavailableReason == nil)
    #expect(result.grades == nil)
  }

  @Test func conditionsDoNotTurnReactionOrErAssumptionsIntoKnownBuildFacts() throws {
    let piece = try flower()
    let nahida = try match(piece, "nahida")
    let fischl = try match(piece, "fischl")
    let raiden = try match(piece, "raiden-shogun")
    #expect(nahida.potential?.currentScore == 6)
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
    #expect(kazuha.potential?.currentScore == 6)
    #expect(kazuha.conditions.contains { $0.kind == .mainStat && $0.status == .unknown })
    #expect(kazuha.conditions.contains { $0.explanation.contains("Favonius") })
    #expect(!CharacterAssessment.evaluate(er).contains { $0.characterID == "sucrose" })
    #expect(!CharacterAssessment.evaluate(er).contains { $0.characterID == "raiden-shogun" })
  }

  @Test(arguments: ["kazuha", "sucrose", "bennett", "raiden-shogun"])
  func favoniusDoesNotMakeCritCircletsStandardSupportMains(id: String) throws {
    let piece = try Artifact(
      setName: "Test off-piece", slot: .circlet, main: .critRate, level: 0,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.hpPercent, 5.83),
        Substat(.energyRecharge, 6.48), Substat(.def, 23.15),
      ])
    #expect(!CharacterAssessment.evaluate(piece).contains { $0.characterID == id })
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
    #expect(forecast.grades == nil)
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
    ("furina", 1.0), ("itto", 0.0), ("kokomi", 1.0), ("kuki-shinobu", 6.0), ("xiangling", 6.0),
  ])
  func originalFiveRetainTheirCoreScreensAndRoles(id: String, score: Double) throws {
    let result = try match(flower(), id)
    let original = try #require(CharacterRoles.pilot.first { $0.characterID == id })
    #expect(result.roleID == original.roleID)
    #expect(result.profile.weights == original.profile.weights)
    #expect(result.potential?.currentScore == score)
  }
}
