import Testing

@testable import ArtifactCore
@testable import ArtifactLens

private func grades(share: Double?, drops: Double?) -> CharacterGradeSummary {
  CharacterGradeSummary(
    current: nil, p50: nil, p90: nil, bestPossible: nil, chanceOfAOrBetter: nil,
    rarityShare: share, replacementDrops: drops, calibrationID: "test", experimental: true)
}

@Test func rarityLineNamesTheComparisonPoolAndRoundsTheReplacementEstimate() throws {
  let goblet = try Artifact(
    setName: "Test", slot: .goblet, main: .hydroDamage, level: 20,
    substats: [
      Substat(.hpPercent, 17.5), Substat(.critRate, 11.7), Substat(.critDamage, 15.5),
      Substat(.energyRecharge, 6.5),
    ])
  #expect(
    rarityLine(grades(share: 0.032, drops: 6234), artifact: goblet)
      == "Top 3.2% of new Hydro Dmg Bonus goblets · about 6,200 domain drops to beat")
  #expect(
    rarityLine(grades(share: 0.032, drops: 6234), artifact: goblet, compact: true)
      == "Top 3.2% of new Hydro Dmg Bonus goblets · ~6,200 drops to beat")
  #expect(
    rarityLine(grades(share: 0.0001, drops: nil), artifact: goblet)
      == "Top <0.1% of new Hydro Dmg Bonus goblets · no new drop beats it")
  #expect(rarityLine(grades(share: nil, drops: nil), artifact: goblet) == nil)
  #expect(rarityLine(nil, artifact: goblet) == nil)
}

@Test func unfinishedPiecesDescribeTheirMedianAndWeakOnesSayBottomHalf() throws {
  let flower = try Artifact(
    setName: "Test", slot: .flower, main: .hp, level: 4,
    substats: [
      Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.hpPercent, 5.83),
      Substat(.energyRecharge, 12.96),
    ])
  #expect(
    rarityLine(grades(share: 0.8, drops: 12.5), artifact: flower)
      == "Median +20: bottom half of new HP flowers · about 13 domain drops to beat")
}

@Test func roughCountKeepsTwoSignificantFigures() {
  #expect(roughCount(9.6) == "10")
  #expect(roughCount(99) == "99")
  #expect(roughCount(149) == "150")
  #expect(roughCount(28_571) == "29,000")
}

@Test func finishedSpecialRulePiecesKeepTheirRarityWithoutAForecast() throws {
  let flower = try Artifact(
    setName: "Test", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.elementalMastery, 116.55), Substat(.atk, 38.90), Substat(.def, 23.15),
      Substat(.hpPercent, 5.83),
    ], rule: .special)
  let kuki = try #require(
    CharacterAssessment.evaluate(flower).first { $0.characterID == "kuki-shinobu" })
  #expect(kuki.potential == nil)
  #expect(kuki.grades?.current == .s)
  #expect(
    rarityLine(kuki.grades, artifact: flower)?.hasPrefix("Top <0.1% of new HP flowers") == true)
}
