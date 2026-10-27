import Foundation
import Testing

@testable import LoupeCore

@Suite struct FourStarTests {
  private func piece(
    _ set: String, _ slot: Slot, _ main: Stat, level: Int, _ substats: [Substat],
    unactivated: Substat? = nil
  ) throws -> Artifact {
    try Artifact(
      setName: set, slot: slot, main: main, level: level, substats: substats,
      unactivated: unactivated, rarity: 4)
  }

  /// A finished four-star sands: three ER rolls and one roll on each of three other lines.
  private func finishedSands(_ set: String = "Instructor", main: Stat = .elementalMastery) throws
    -> Artifact
  {
    try piece(
      set, .sands, main, level: 16,
      [
        Substat(.energyRecharge, 12.43), Substat(.hpPercent, 3.73), Substat(.def, 14.82),
        Substat(.critRate, 2.80),
      ])
  }

  @Test func fourStarPiecesUseTheirOwnRollsLinesAndLevelCap() throws {
    // Two lines at +0, a third at +4, four from +8.
    let starter = try piece(
      "Instructor", .sands, .elementalMastery, level: 0,
      [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)])
    #expect(starter.rarity == 4)
    #expect(starter.maxLevel == 16)
    #expect(starter.nextCheckpoint == 4)
    #expect(try finishedSands().isFinished)
    #expect(throws: ArtifactError.self) {
      try piece(
        "Instructor", .sands, .elementalMastery, level: 20,
        [
          Substat(.energyRecharge, 12.43), Substat(.hpPercent, 3.73), Substat(.def, 14.82),
          Substat(.critRate, 2.80),
        ])
    }
    // A five-star CRIT Rate roll is not a four-star value.
    #expect(throws: ArtifactError.self) {
      try piece(
        "Instructor", .sands, .elementalMastery, level: 0,
        [Substat(.energyRecharge, 4.14), Substat(.critRate, 3.89)])
    }
    #expect(throws: ArtifactError.self) {
      try piece(
        "Instructor", .sands, .elementalMastery, level: 4,
        [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)])
    }
    #expect(throws: ArtifactError.self) {
      try Artifact(
        setName: "Adventurer", slot: .flower, main: .hp, level: 0,
        substats: [Substat(.atk, 10.89)], rarity: 3)
    }
  }

  @Test func upgradesAddLinesUntilThereAreFour() throws {
    let starter = try piece(
      "Instructor", .sands, .elementalMastery, level: 0,
      [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)])
    let four = try piece(
      "Instructor", .sands, .elementalMastery, level: 4,
      [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49), Substat(.def, 14.82)])
    let eight = try piece(
      "Instructor", .sands, .elementalMastery, level: 8,
      [
        Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49), Substat(.def, 14.82),
        Substat(.hpPercent, 3.73),
      ])
    let twelve = try piece(
      "Instructor", .sands, .elementalMastery, level: 12,
      [
        Substat(.energyRecharge, 8.28), Substat(.critRate, 2.49), Substat(.def, 14.82),
        Substat(.hpPercent, 3.73),
      ])
    #expect(try starter.upgraded(to: four).id == starter.id)
    #expect(try four.upgraded(to: eight).substats.count == 4)
    #expect(try starter.upgraded(to: eight).level == 8)
    #expect(try eight.upgraded(to: twelve).substats.first?.value == 8.28)
    // A line cannot vanish, and a value cannot change without a roll.
    #expect(throws: ArtifactError.self) { try eight.upgraded(to: four) }
    let five = try Artifact(
      setName: "Instructor", slot: .sands, main: .elementalMastery, level: 8,
      substats: [
        Substat(.energyRecharge, 10.36), Substat(.critRate, 3.11), Substat(.def, 18.52),
        Substat(.hpPercent, 4.66),
      ])
    #expect(throws: ArtifactError.self) { try four.upgraded(to: five) }
  }

  @Test func linesAndRollsMustAgree() throws {
    // Three lines at +4 mean the upgrade added a line, so no line can hold two rolls.
    #expect(throws: ArtifactError.self) {
      try piece(
        "Instructor", .sands, .elementalMastery, level: 4,
        [Substat(.energyRecharge, 8.28), Substat(.critRate, 2.49), Substat(.def, 14.82)])
    }
    // Four lines at +4 mean a three-line start whose upgrade added the fourth: still no rolls.
    #expect(
      try piece(
        "Instructor", .sands, .elementalMastery, level: 4,
        [
          Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49), Substat(.def, 14.82),
          Substat(.hpPercent, 3.73),
        ]
      ).level == 4)
    #expect(throws: ArtifactError.self) {
      try piece(
        "Instructor", .sands, .elementalMastery, level: 4,
        [
          Substat(.energyRecharge, 8.28), Substat(.critRate, 2.49), Substat(.def, 14.82),
          Substat(.hpPercent, 3.73),
        ])
    }
  }

  @Test func aLinkedRecordFollowsLinesThatWereAddedAndThenRolled() throws {
    let starter = try piece(
      "Instructor", .sands, .elementalMastery, level: 0,
      [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)])
    // DEF arrived at +4, HP% at +8, and DEF rolled again at +12.
    let twelve = try piece(
      "Instructor", .sands, .elementalMastery, level: 12,
      [
        Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49), Substat(.def, 29.64),
        Substat(.hpPercent, 3.73),
      ])
    #expect(try starter.upgraded(to: twelve).id == starter.id)
    // One roll too many for three upgrades.
    let tooMany = try piece(
      "Instructor", .sands, .elementalMastery, level: 12,
      [
        Substat(.energyRecharge, 8.28), Substat(.critRate, 2.49), Substat(.def, 29.64),
        Substat(.hpPercent, 3.73),
      ])
    #expect(throws: ArtifactError.self) { try starter.upgraded(to: tooMany) }
  }

  @Test func enhanceFollowsALineAddedBelowTheOthers() throws {
    let previous = try CardParser.parse(
      """
      Instructor's Pocket Watch
      Sands of Eon
      Elemental Mastery
      70
      +4
      Energy Recharge+4.1%
      CRIT Rate+2.5%
      DEF+15
      Instructor:
      """, stars: 4)
    let screen = """
      Sands of Eon / Instructor's Pocket Watch
      +8
      Elemental Mastery+93
      Energy Recharge+4.1%
      CRIT Rate+2.5%
      DEF+15
      HP+3.7%
      """
    let updated = try CardParser.parseEnhancement(
      screen, previous: previous, pieceName: "Instructor's Pocket Watch")
    #expect(updated.level == 8)
    #expect(updated.rarity == 4)
    #expect(updated.substats.map(\.key) == [.energyRecharge, .critRate, .def, .hpPercent])
    // A missed row cannot pass as a smaller piece.
    let missing = """
      Sands of Eon / Instructor's Pocket Watch
      +4
      Elemental Mastery+70
      Energy Recharge+4.1%
      DEF+15
      """
    #expect(throws: ArtifactError.self) {
      try CardParser.parseEnhancement(
        missing, previous: previous, pieceName: "Instructor's Pocket Watch")
    }
  }

  @Test func savedInventoryKeepsRarityAndOldRecordsStayFiveStar() throws {
    let saved = try finishedSands()
    let decoded = try JSONDecoder().decode(Artifact.self, from: JSONEncoder().encode(saved))
    #expect(decoded == saved)
    #expect(decoded.rarity == 4)
    #expect(saved.signature != (try finishedFiveStar()).signature)
    var legacy =
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(try finishedFiveStar())) as! [String: Any]
    legacy["rarity"] = nil
    let old = try JSONDecoder().decode(
      Artifact.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.rarity == 5)
  }

  private func finishedFiveStar() throws -> Artifact {
    try Artifact(
      setName: "Instructor", slot: .sands, main: .elementalMastery, level: 20,
      substats: [
        Substat(.energyRecharge, 25.92), Substat(.hpPercent, 5.83), Substat(.def, 23.15),
        Substat(.critRate, 3.89),
      ])
  }

  @Test func cardsWithFourStarsParseAndOtherCountsDoNot() throws {
    let text = """
      Instructor's Pocket Watch
      Sands of Eon
      Elemental Mastery
      139
      +16
      Energy Recharge+12.4%
      HP+3.7%
      DEF+15
      CRIT Rate+2.8%
      Instructor:
      """
    let artifact = try CardParser.parse(text, stars: 4)
    #expect(artifact.rarity == 4)
    #expect(artifact.isFinished)
    #expect(throws: ArtifactError.self) { try CardParser.parse(text, stars: 3) }
    #expect(throws: ArtifactError.self) { try CardParser.parse(text, fiveStarsConfirmed: false) }
  }

  @Test func goodImportsKeepFourStarsAndSkipLowerRarities() throws {
    let json = """
      {"format": "GOOD", "artifacts": [
        {"setKey": "Instructor", "slotKey": "sands", "mainStatKey": "eleMas", "level": 16,
         "rarity": 4, "substats": [{"key": "enerRech_", "value": 12.4},
         {"key": "hp_", "value": 3.7}, {"key": "def", "value": 15}, {"key": "critRate_", "value": 2.8}]},
        {"setKey": "Adventurer", "slotKey": "flower", "mainStatKey": "hp", "level": 0,
         "rarity": 3, "substats": []}
      ]}
      """
    let imported = try Inventory.importGOOD(Data(json.utf8))
    #expect(imported.artifacts.map(\.rarity) == [4])
    #expect(imported.artifacts.first?.setKey == Artifact.normalizeSet("Instructor"))
    #expect(imported.skipped == 1)
  }

  @Test func fourStarsHaveNoRollOddsOrGrades() throws {
    let artifact = try finishedSands()
    #expect(throws: ArtifactError.self) { try RollOutcomes(artifact) }
    let matches = CharacterAssessment.evaluate(artifact)
    #expect(!matches.isEmpty)
    // Only characters whose build lists Instructor match, and none gets odds or a grade.
    #expect(
      matches.allSatisfy { match in
        match.role.sets.contains { $0.name == "Instructor" } && match.potential == nil
          && match.grades == nil
          && match.potentialUnavailableReason == RollOutcomes.fourStarReason
      })
    #expect(Set(matches.map(\.characterID)).isSuperset(of: ["kuki-shinobu", "nahida"]))
    #expect(CharacterAssessment.evaluate(try finishedSands("Gambler")).isEmpty)
  }

  @Test func aNeededFourStarIsLeveledAndKeptUntilThereAreTwo() throws {
    let starter = try piece(
      "Instructor", .sands, .elementalMastery, level: 0,
      [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)])
    func verdict(_ artifact: Artifact, saved: [Artifact] = []) -> Verdict {
      VerdictEngine.evaluate(
        artifact, matches: CharacterAssessment.evaluate(artifact), inventory: saved)
    }
    let level = verdict(starter)
    #expect(level.title == "Level to +16")
    #expect(level.reason == "Four-star Instructor · 0 saved like it")
    #expect(level.characterID != nil)
    let finished = try finishedSands()
    #expect(verdict(finished).kind == .keep)
    let copies = [try finished.withID(UUID()), try finished.withID(UUID())]
    let enough = verdict(finished, saved: copies)
    #expect(enough.kind == .fodder)
    #expect(enough.reason == "Enough saved Instructor Elemental Mastery sands")
    #expect(!enough.standings.isEmpty)
    #expect(enough.standings.values.allSatisfy { $0 == .covered(2) })
    // A saved copy with fewer useful lines leaves room to compare.
    let weaker = try piece(
      "Instructor", .sands, .elementalMastery, level: 16,
      [
        Substat(.atk, 37.34), Substat(.atkPercent, 3.73), Substat(.def, 14.82),
        Substat(.critRate, 2.80),
      ])
    let review = verdict(finished, saved: [weaker, try finished.withID(UUID())])
    #expect(review.kind == .review)
    // The candidate's own saved record is not a copy.
    #expect(
      VerdictEngine.evaluate(
        finished, matches: CharacterAssessment.evaluate(finished), inventory: copies,
        excluding: copies[0].id
      ).kind == .keep)
  }

  @Test func anyEligibleCharacterCanWantAThirdCopy() throws {
    // Saved copies suit Kuki (HP%, ER); the candidate's crit and ATK% lines suit Nahida.
    let saved = try (0..<2).map { _ in
      try piece(
        "Instructor", .sands, .elementalMastery, level: 16,
        [
          Substat(.hpPercent, 3.73), Substat(.energyRecharge, 12.43), Substat(.atk, 14.00),
          Substat(.def, 14.82),
        ])
    }
    let candidate = try piece(
      "Instructor", .sands, .elementalMastery, level: 16,
      [
        Substat(.critRate, 6.22), Substat(.critDamage, 9.94), Substat(.atkPercent, 3.73),
        Substat(.def, 14.82),
      ])
    let verdict = VerdictEngine.evaluate(
      candidate, matches: CharacterAssessment.evaluate(candidate), inventory: saved)
    #expect(verdict.kind == .review)
    #expect(verdict.characterID == "nahida")
    // Roles the saved copies already suit are covered; the one wanting another copy is open.
    #expect(verdict.standings[verdict.roleID ?? ""] == nil)
    let kuki = try #require(
      CharacterAssessment.evaluate(candidate).first { $0.characterID == "kuki-shinobu" })
    #expect(verdict.standings[kuki.roleID] == .covered(2))
  }

  @Test func otherFourStarsAreFodderWithAReason() throws {
    func verdict(_ artifact: Artifact) -> Verdict {
      VerdictEngine.evaluate(
        artifact, matches: CharacterAssessment.evaluate(artifact), inventory: [])
    }
    #expect(
      verdict(try finishedSands("Gambler")).reason == "Four-star Gambler is an early-game set")
    let goblet = try piece(
      "Instructor", .goblet, .atkPercent, level: 16,
      [
        Substat(.energyRecharge, 12.43), Substat(.hpPercent, 3.73), Substat(.def, 14.82),
        Substat(.critRate, 2.80),
      ])
    #expect(verdict(goblet).kind == .fodder)
    #expect(verdict(goblet).reason == "Four-star; no Instructor user takes ATK% goblets")
  }

  @Test func fourStarSupportSetsAreListedForTheCharactersGuidesName() {
    func sets(_ id: String) -> Set<String> {
      Set(
        CharacterRoles.all.filter { $0.characterID == id }.flatMap { $0.sets.map(\.name) })
    }
    for id in [
      "bennett", "kuki-shinobu", "nahida", "kirara", "baizhu", "traveler-dendro", "yaoyao",
      "xilonen", "zhongli",
    ] {
      #expect(sets(id).contains("Instructor"), "\(id)")
    }
    for id in ["bennett", "faruzan", "gorou", "yaoyao"] {
      #expect(sets(id).contains("The Exile"), "\(id)")
    }
    // Venerer is the set guides give Kazuha and Sucrose; Instructor is not listed.
    #expect(!sets("kazuha").contains("Instructor"))
    #expect(!sets("sucrose").contains("Instructor"))
    // Four-star sets are always alternatives.
    #expect(
      CharacterRoles.all.flatMap(\.sets).filter { ["Instructor", "The Exile"].contains($0.name) }
        .allSatisfy { $0.fit == .alternative })
  }
}
