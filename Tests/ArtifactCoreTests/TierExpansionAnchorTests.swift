import ArtifactCore
import Testing

@Suite struct TierExpansionAnchorTests {
  private func artifact(
    _ slot: Slot, _ main: Stat, _ stats: [Substat], level: Int = 20
  ) throws -> Artifact {
    try Artifact(
      setName: "Synthetic off-piece", slot: slot, main: main, level: level, substats: stats)
  }

  private func profile(_ characterID: String) throws -> Profile {
    try #require(CharacterRoles.pilot.first { $0.characterID == characterID }).profile
  }

  private func assertFinalScore(_ piece: Artifact, profile: Profile, expected: Int) throws {
    let result = try Potential.evaluate(piece, profile: profile, inventory: [], scope: .offPiece)
    #expect(profile.score(piece.substats) == expected)
    #expect(result.distribution == [expected: 1])
    #expect(abs(result.currentScore - Double(expected) / 1000) < 0.000_001)
    #expect(result.summary.p50Score == result.currentScore)
    #expect(result.summary.p90Score == result.currentScore)
    #expect(result.summary.bestPossibleScore == result.currentScore)
    #expect(result.comparisonCount == 0)
    #expect(result.chanceToBeatBest == nil)
  }

  /// The hand-reviewed anchors sit exactly on their former cutoffs. Rarity-derived cutoffs land
  /// within a third of a roll of them for B, A, and S, so each anchor stays within one tier.
  private func assertFinalGrade(
    _ piece: Artifact, character: String, handTier: ArtifactTier
  ) throws {
    let match = try #require(
      CharacterAssessment.evaluate(piece).first { $0.characterID == character })
    let grades = try #require(match.grades)
    let current = try #require(grades.current)
    let tiers = ArtifactTier.allCases
    #expect(grades.calibrationID.hasPrefix(RarityTier.version))
    #expect(grades.experimental)
    #expect(abs(tiers.firstIndex(of: current)! - tiers.firstIndex(of: handTier)!) <= 1)
    #expect(grades.p50 == current)
    #expect(grades.p90 == current)
    #expect(grades.bestPossible == current)
    #expect(grades.chanceOfAOrBetter == (current == .a || current == .s ? 1 : 0))
    #expect(grades.rarityShare != nil)
  }

  @Test(arguments: [
    (5.83, 7.29, 0.0, 0.0, 29.15, 46.30, 6.48, 1000, ArtifactTier.d),
    (8.16, 10.20, 0.0, 0.0, 23.32, 46.30, 6.48, 1400, .c),
    (19.82, 24.78, 0.0, 0.0, 17.49, 23.15, 6.48, 3400, .c),
    (20.40, 25.50, 0.0, 0.0, 11.66, 23.15, 6.48, 3500, .b),
    (23.32, 29.16, 5.83, 0.0, 0.0, 46.30, 6.48, 5500, .b),
    (23.32, 29.16, 6.22, 0.0, 0.0, 46.30, 6.48, 5600, .a),
    (17.49, 21.87, 7.78, 14.76, 0.0, 0.0, 12.96, 6900, .a),
    (17.49, 21.87, 7.78, 15.54, 0.0, 0.0, 12.96, 7000, .s),
  ])
  func threeCoreFlowerAndPlumeBoundaries(
    hp: Double, defPercent: Double, cr: Double, cd: Double, atkPercent: Double,
    def: Double, er: Double, expected: Int, tier: ArtifactTier
  ) throws {
    for (character, scaling, value) in [
      ("furina", Stat.hpPercent, hp), ("itto", .defPercent, defPercent),
    ] {
      let stats = [
        Substat(scaling, value), Substat(.critRate, cr), Substat(.critDamage, cd),
        Substat(.atkPercent, atkPercent), Substat(.def, def), Substat(.energyRecharge, er),
      ].filter { $0.value > 0 }
      for (slot, main) in [(Slot.flower, Stat.hp), (.plume, .atk)] {
        let piece = try artifact(slot, main, stats)
        try assertFinalScore(
          piece, profile: profile(character), expected: expected)
        try assertFinalGrade(piece, character: character, handTier: tier)
      }
    }
  }

  @Test(arguments: [
    (5.83, 7.29, 3.89, 0.0, 0.0, 29.15, 46.30, 6.48, 1000, ArtifactTier.d),
    (8.16, 10.20, 5.44, 0.0, 0.0, 23.32, 46.30, 6.48, 1400, .c),
    (15.75, 19.68, 10.50, 0.0, 0.0, 23.32, 23.15, 6.48, 2700, .c),
    (16.33, 20.41, 10.89, 0.0, 0.0, 23.32, 23.15, 6.48, 2800, .b),
    (23.32, 29.16, 15.56, 6.22, 3.11, 0.0, 46.30, 12.96, 4800, .b),
    (23.32, 29.16, 15.56, 6.99, 3.50, 0.0, 46.30, 12.96, 4900, .a),
    (23.32, 29.16, 15.56, 14.76, 7.39, 0.0, 23.15, 12.96, 5900, .a),
    (23.32, 29.16, 15.56, 15.54, 7.78, 0.0, 23.15, 12.96, 6000, .s),
  ])
  func twoCoreScalingMainsAndCritCircletBoundaries(
    hp: Double, defPercent: Double, cr: Double, otherCD: Double, otherCR: Double,
    atkPercent: Double, def: Double, er: Double, expected: Int, tier: ArtifactTier
  ) throws {
    let cells: [(String, Slot, Stat, Stat, Double, Stat, Double)] = [
      ("furina", .sands, .hpPercent, .critRate, cr, .critDamage, otherCD),
      ("furina", .goblet, .hpPercent, .critRate, cr, .critDamage, otherCD),
      ("itto", .sands, .defPercent, .critRate, cr, .critDamage, otherCD),
      ("furina", .circlet, .critRate, .hpPercent, hp, .critDamage, otherCD),
      ("furina", .circlet, .critDamage, .hpPercent, hp, .critRate, otherCR),
      ("itto", .circlet, .critRate, .defPercent, defPercent, .critDamage, otherCD),
      ("itto", .circlet, .critDamage, .defPercent, defPercent, .critRate, otherCR),
    ]
    for (character, slot, main, first, value, second, other) in cells {
      let stats = [
        Substat(first, value), Substat(second, other), Substat(.atkPercent, atkPercent),
        Substat(.def, def), Substat(.energyRecharge, er),
      ].filter { $0.value > 0 }
      let piece = try artifact(slot, main, stats)
      try assertFinalScore(piece, profile: profile(character), expected: expected)
      try assertFinalGrade(piece, character: character, handTier: tier)
    }
  }

  @Test(arguments: [
    (0.0, 29.15, 46.30, 6.48, 7.77, 0),
    (16.32, 29.15, 46.30, 6.48, 0.0, 700),
    (46.62, 29.15, 23.15, 6.48, 0.0, 2000),
    (48.96, 23.32, 23.15, 6.48, 0.0, 2100),
    (79.26, 17.49, 23.15, 6.48, 0.0, 3400),
    (81.60, 11.66, 23.15, 6.48, 0.0, 3500),
    (111.89, 11.66, 23.15, 6.48, 0.0, 4800),
    (114.22, 11.66, 23.15, 6.48, 0.0, 4900),
  ])
  func emOnlyBoundaryMathDoesNotRequireANewCharacterRole(
    em: Double, atkPercent: Double, def: Double, er: Double, cd: Double, expected: Int
  ) throws {
    let stats = [
      Substat(.elementalMastery, em), Substat(.atkPercent, atkPercent), Substat(.def, def),
      Substat(.energyRecharge, er), Substat(.critDamage, cd),
    ].filter { $0.value > 0 }
    for (slot, main) in [(Slot.flower, Stat.hp), (.plume, .atk)] {
      try assertFinalScore(
        artifact(slot, main, stats),
        profile: Profile("Synthetic EM-only screen", weights: [.elementalMastery: 100]),
        expected: expected)
    }
  }

  @Test(arguments: [
    (5, 2915, 1945, 11655, 7000, 6000, 5000),
    (6, 3498, 2334, 13986, 8000, 7000, 6000),
  ])
  func bothStarterOriginsReachTheirCellCeilings(
    rolls: Int, hpHundredths: Int, crHundredths: Int, emHundredths: Int,
    threeCore: Int, twoCore: Int, oneCore: Int
  ) throws {
    let hp = Substat(.hpPercent, Double(hpHundredths) / 100)
    let cr = Substat(.critRate, Double(crHundredths) / 100)
    let em = Substat(.elementalMastery, Double(emHundredths) / 100)
    #expect(Artifact.possibleRollCounts(hp).contains(rolls))
    #expect(Artifact.possibleRollCounts(cr).contains(rolls))
    #expect(Artifact.possibleRollCounts(em).contains(rolls))
    try assertFinalScore(
      artifact(
        .flower, .hp,
        [
          hp, Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
          Substat(.energyRecharge, 6.48),
        ]), profile: profile("furina"), expected: threeCore)
    try assertFinalScore(
      artifact(
        .sands, .hpPercent,
        [
          cr, Substat(.critDamage, 7.77), Substat(.def, 23.15),
          Substat(.energyRecharge, 6.48),
        ]), profile: profile("furina"), expected: twoCore)
    try assertFinalScore(
      artifact(
        .flower, .hp,
        [
          em, Substat(.atk, 19.45), Substat(.def, 23.15),
          Substat(.energyRecharge, 6.48),
        ]),
      profile: Profile("Synthetic EM-only screen", weights: [.elementalMastery: 100]),
      expected: oneCore)
  }

  @Test func unfinishedMedianStaysBelowCeilingAndUsefulUpgradeIsMonotone() throws {
    let before = try artifact(
      .sands, .hpPercent,
      [
        Substat(.critRate, 15.56), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 12.96),
      ], level: 16)
    let after = try artifact(
      .sands, .hpPercent,
      [
        Substat(.critRate, 19.45), Substat(.critDamage, 7.77), Substat(.def, 23.15),
        Substat(.energyRecharge, 12.96),
      ])
    let fixedProfile = try profile("furina")
    let result = try Potential.evaluate(
      before, profile: fixedProfile, inventory: [], scope: .offPiece)
    #expect(result.distribution == [5000: 0.5, 5700: 0.125, 5800: 0.125, 5900: 0.125, 6000: 0.125])
    #expect(result.summary.p50Score == 5)
    #expect(result.summary.p90Score == 6)
    #expect(result.summary.bestPossibleScore == 6)
    #expect(fixedProfile.score(after.substats) > fixedProfile.score(before.substats))
    #expect(try before.upgraded(to: after).substats == after.substats)
    try assertFinalScore(after, profile: fixedProfile, expected: 6000)
  }

  @Test func excludedMainAndImpossibleRollTotalAreRejected() throws {
    #expect(throws: ArtifactError.self) {
      try artifact(
        .sands, .hpPercent,
        [
          Substat(.hpPercent, 34.98), Substat(.critRate, 3.89), Substat(.def, 23.15),
          Substat(.energyRecharge, 6.48),
        ])
    }
    #expect(throws: ArtifactError.self) {
      try artifact(
        .sands, .hpPercent,
        [
          Substat(.critRate, 3.89), Substat(.critDamage, 7.77), Substat(.def, 23.15),
          Substat(.energyRecharge, 6.48),
        ])
    }
  }
}
