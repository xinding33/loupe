import Testing

@testable import Loupe
@testable import LoupeCore

private func grades(share: Double?, drops: Double?) -> CharacterGradeSummary {
  CharacterGradeSummary(
    grade: .b, chanceOfAOrBetter: nil, rarityShare: share, p90Share: nil, bestShare: nil,
    replacementDrops: drops, calibrationID: "test", experimental: true)
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
      == "Top 3.2% of new Hydro Dmg Bonus goblets · ~650 days of resin to beat (~120,000 resin)")
  #expect(
    rarityLine(grades(share: 0.032, drops: 6234), artifact: goblet, compact: true)
      == "Top 3.2% of new Hydro Dmg Bonus goblets · ~650 days of resin to beat")
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
      == "Median +20: bottom half of new HP flowers · ~1 day of resin to beat (~230 resin)")
}

@Test func rarityHelpGivesTheCountsAndAssumptions() {
  #expect(
    rarityHelp(grades(share: 0.1, drops: 110))
      == "~2,100 resin, ~100 runs, ~110 five-star drops. Assumes top-level domain runs of this set: "
      + "~1.07 five-stars per 20 resin, 180 resin a day.")
  #expect(rarityHelp(grades(share: 0.1, drops: nil)) == nil)
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
  #expect(kuki.grades?.grade == .s)
  #expect(
    rarityLine(kuki.grades, artifact: flower)?.hasPrefix("Top <0.1% of new HP flowers") == true)
}

@Test func sandsAreAlreadyPlural() throws {
  let sands = try Artifact(
    setName: "Test", slot: .sands, main: .hpPercent, level: 20,
    substats: [
      Substat(.critRate, 11.67), Substat(.critDamage, 7.77), Substat(.def, 46.30),
      Substat(.energyRecharge, 12.96),
    ])
  #expect(
    rarityLine(grades(share: 0.1, drops: 50), artifact: sands)
      == "Top 10.0% of new HP% sands · ~5 days of resin to beat (~940 resin)")
}

@Test func compactVerdictNamesItsCharacterWhenAnotherIsSelected() throws {
  let flower = try Artifact(
    setName: "Gilded Dreams", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.elementalMastery, 116.55), Substat(.hpPercent, 5.83), Substat(.critRate, 7.78),
      Substat(.def, 23.15),
    ])
  let verdict = VerdictEngine.evaluate(
    flower, matches: CharacterAssessment.evaluate(flower), inventory: [])
  let id = try #require(verdict.characterID)
  let name = try #require(verdict.characterName)
  #expect(VerdictBanner.text(verdict, lines: 1, displayedCharacterID: id) == verdict.reason)
  #expect(
    VerdictBanner.text(verdict, lines: 1, displayedCharacterID: "someone-else")
      == "\(name) · \(verdict.reason)")
  #expect(VerdictBanner.text(verdict, lines: 2, displayedCharacterID: id) == verdict.summary)
}

@MainActor
@Test func bannerNamesTheVerdictsRoleWhenAnotherRoleOfTheCharacterIsShown() throws {
  let flower = try Artifact(
    setName: "Obsidian Codex", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.elementalMastery, 139.86), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
      Substat(.atk, 19.45),
    ])
  let verdict = VerdictEngine.evaluate(
    flower, matches: CharacterAssessment.evaluate(flower), inventory: [])
  let character = try #require(verdict.characterID)
  let role = try #require(verdict.roleID)
  #expect(
    VerdictBanner.text(verdict, lines: 1, displayedCharacterID: character, displayedRoleID: role)
      == verdict.reason)
  let other = VerdictBanner.text(
    verdict, lines: 1, displayedCharacterID: character, displayedRoleID: "\(character).other")
  #expect(other.contains(try #require(verdict.roleName)))
  #expect(other.hasSuffix(verdict.reason))
  // Two lines, as the dashboard and the accessibility label use, still name the role.
  #expect(
    VerdictBanner.text(
      verdict, lines: 2, displayedCharacterID: character, displayedRoleID: "\(character).other")
      == other)
}
