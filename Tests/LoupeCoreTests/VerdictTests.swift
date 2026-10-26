import Foundation
import Testing

@testable import LoupeCore

struct VerdictTests {
  /// Test-only roles with controlled useful stats, so expectations do not depend on reviewed data.
  private static func match(
    _ id: String, _ artifact: Artifact, useful: [Stat], setFit: CharacterSetFit = .offPiece
  ) -> CharacterMatch {
    let role = CharacterRole(
      characterID: id, characterName: id.capitalized, roleID: id + ".synthetic",
      roleName: "Synthetic verdict test", mains: [artifact.slot: [artifact.main]],
      usefulStats: useful, secondaryStats: [], sets: [], conditions: [],
      source: RoleSource(
        url: "https://example.invalid/synthetic", section: "Synthetic test only",
        sourceVersion: "test", reviewedOn: "2026-10-22"))
    return CharacterMatch(
      role: role, setFit: setFit, conditions: [], reasons: [], potential: nil,
      potentialUnavailableReason: nil, grades: nil)
  }

  /// A finished HP flower whose only useful line for an EM role is `emRolls` maximum EM rolls.
  private static func emFlower(_ emRolls: Int, level: Int = 20) throws -> Artifact {
    // Spread the remaining rolls of a four-line start over three junk lines, at most six each.
    let others = 4 + level / 4 - max(emRolls, 1)
    let atk = min(6, others - 2)
    let def = min(6, others - atk - 1)
    var stats = [
      Substat(.atk, 19.45 * Double(atk)), Substat(.def, 23.15 * Double(def)),
      Substat(.energyRecharge, 6.48 * Double(others - atk - def)),
    ]
    if emRolls > 0 {
      stats.append(Substat(.elementalMastery, 23.31 * Double(emRolls)))
    } else {
      stats.append(Substat(.hpPercent, 5.83))
    }
    return try Artifact(setName: "Test", slot: .flower, main: .hp, level: level, substats: stats)
  }

  @Test func noMatchingRoleIsFodder() throws {
    let piece = try Self.emFlower(2)
    let verdict = VerdictEngine.evaluate(piece, matches: [], inventory: [])
    #expect(verdict.kind == .fodder)
    #expect(verdict.reason == "No character role uses HP flowers")
  }

  @Test func aPieceNoNewDropCanBeatIsKept() throws {
    let piece = try Self.emFlower(6)
    let verdict = VerdictEngine.evaluate(
      piece, matches: [Self.match("em", piece, useful: [.elementalMastery])], inventory: [])
    #expect(verdict.kind == .keep)
    #expect(verdict.characterID == "em")
    #expect(verdict.reason == "No new drop beats it")
    #expect(verdict.characterName == "Em")
    #expect(verdict.summary == "Em · No new drop beats it")
  }

  @Test func aPieceThatTakesThousandsOfDropsToReplaceIsKept() throws {
    let piece = try Self.emFlower(5)
    let verdict = VerdictEngine.evaluate(
      piece, matches: [Self.match("em", piece, useful: [.elementalMastery])], inventory: [])
    #expect(verdict.kind == .keep)
    #expect(verdict.reason.hasPrefix("About "))
    #expect(verdict.reason.hasSuffix(" drops to replace"))
  }

  @Test func bottomHalfForEveryRoleIsFodder() throws {
    let piece = try Self.emFlower(0)
    let verdict = VerdictEngine.evaluate(
      piece, matches: [Self.match("em", piece, useful: [.elementalMastery])], inventory: [])
    #expect(verdict.kind == .fodder)
    #expect(verdict.reason == "Bottom half of new HP flowers for every role")
  }

  @Test func aGoodPieceWithoutSavedComparablesAsksForABaseline() throws {
    let piece = try Self.emFlower(3)
    let verdict = VerdictEngine.evaluate(
      piece, matches: [Self.match("em", piece, useful: [.elementalMastery])], inventory: [])
    #expect(verdict.kind == .review)
    #expect(verdict.reason.hasSuffix("; no saved +20 HP flowers to compare yet"))
  }

  @Test func beatingTheSavedPoolKeepsAndBeingBeatenFeeds() throws {
    let piece = try Self.emFlower(3)
    let em = Self.match("em", piece, useful: [.elementalMastery])
    let weaker = try Self.emFlower(1)
    let stronger = try Self.emFlower(4)
    let keep = VerdictEngine.evaluate(piece, matches: [em], inventory: [weaker])
    #expect(keep.kind == .keep)
    #expect(keep.reason == "Beats all 1 saved HP flowers")
    let tied = VerdictEngine.evaluate(piece, matches: [em], inventory: [try piece.withID(UUID())])
    #expect(tied.kind == .keep)
    #expect(tied.reason == "Tied for best of 1 saved HP flowers")
    let fodder = VerdictEngine.evaluate(piece, matches: [em], inventory: [stronger])
    #expect(fodder.kind == .fodder)
    #expect(fodder.reason == "Enough saved HP flowers beat it for every role")
    // The candidate's own saved record is not a comparison.
    let own = VerdictEngine.evaluate(
      piece, matches: [em], inventory: [stronger], excluding: stronger.id)
    #expect(own.kind == .review)
  }

  @Test func rolesSharingAProfileShareTheirBackups() throws {
    let piece = try Self.emFlower(3)
    let stronger = try Self.emFlower(4)
    let pair = [
      Self.match("em", piece, useful: [.elementalMastery]),
      Self.match("twin", piece, useful: [.elementalMastery]),
    ]
    let verdict = VerdictEngine.evaluate(piece, matches: pair, inventory: [stronger])
    #expect(verdict.kind == .keep)
    #expect(verdict.reason == "#2 of saved HP flowers")
    var policy = VerdictPolicy()
    policy.maxBackups = 1
    let capped = VerdictEngine.evaluate(
      piece, matches: pair, inventory: [stronger], policy: policy)
    #expect(capped.kind == .fodder)
  }

  @Test func mainStatOnlyFitsKeepUntilTheSavedPoolHasRoom() throws {
    let sands = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 20,
      substats: [
        Substat(.atk, 58.35), Substat(.def, 46.30), Substat(.hp, 597.50),
        Substat(.critRate, 3.89),
      ])
    let other = try sands.withID(UUID())
    let em = Self.match("em", sands, useful: [.elementalMastery])
    let keep = VerdictEngine.evaluate(sands, matches: [em], inventory: [])
    #expect(keep.kind == .keep)
    #expect(keep.reason == "Main stat fills a gap: 0 saved Elemental Mastery sands")
    let covered = VerdictEngine.evaluate(sands, matches: [em], inventory: [other])
    #expect(covered.kind == .review)
  }

  @Test func levelingUsesTheExactKeeperChanceAcrossOutcomes() throws {
    let starter = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.atk, 19.45), Substat(.def, 23.15),
        Substat(.energyRecharge, 6.48),
      ])
    let em = Self.match("em", starter, useful: [.elementalMastery])
    let saved = try Self.emFlower(0)
    let verdict = VerdictEngine.evaluate(starter, matches: [em], inventory: [saved])
    // Brute force: a final outcome keeps when it is rare enough on its own, or B or better and
    // above the single saved piece, which has no EM.
    let rarity = try DropRarity(slot: .flower, main: .hp, profile: em.profile)
    let outcomes = try RollOutcomes(starter)
    let expected = outcomes.probability { outcome in
      let score = outcomes.score(outcome.units, profile: em.profile)
      let drops = rarity.expectedDropsToBeat(score, setChance: 1) ?? .infinity
      return drops >= 1000 || (score > 0 && rarity.shareAtOrAbove(score) <= 0.15)
    }
    #expect(verdict.kind == .level)
    #expect(verdict.targetLevel == 4)
    #expect(abs((verdict.keeperChance ?? -1) - expected) < 1e-12)
    #expect(expected > 0.05 && expected < 1)
    #expect(verdict.reason.hasSuffix("% chance it becomes a keeper"))
    #expect(verdict.summary.hasPrefix("Em · "))

    var strict = VerdictPolicy()
    strict.levelBars = [1, 1, 1, 1, 1]
    let fodder = VerdictEngine.evaluate(starter, matches: [em], inventory: [saved], policy: strict)
    #expect(fodder.kind == .fodder)
    #expect(fodder.keeperChance == verdict.keeperChance)
    #expect(fodder.reason.hasPrefix("Only "))
  }

  @Test func piecesWithoutAForecastAskForReview() throws {
    let incomplete = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.elementalMastery, 23.31), Substat(.atk, 19.45), Substat(.def, 23.15)])
    let em = CharacterMatch(
      role: Self.match("em", incomplete, useful: [.elementalMastery]).role, setFit: .offPiece,
      conditions: [], reasons: [], potential: nil,
      potentialUnavailableReason: "Read or enter the fourth stat", grades: nil)
    let verdict = VerdictEngine.evaluate(incomplete, matches: [em], inventory: [])
    #expect(verdict.kind == .review)
    #expect(verdict.reason == "Read or enter the fourth stat")
    #expect(verdict.keeperChance == nil)
  }

  @Test func onSetRolesAreHarderToReplaceThanOffPieces() throws {
    let piece = try Self.emFlower(4)
    let inventory = [try Self.emFlower(1)]
    func reason(_ fit: CharacterSetFit) -> String {
      VerdictEngine.evaluate(
        piece, matches: [Self.match("em", piece, useful: [.elementalMastery], setFit: fit)],
        inventory: inventory
      ).reason
    }
    // An off-piece can come from any domain, so the same piece is twice as easy to replace.
    #expect(reason(.preferred) != reason(.offPiece))
  }

  @Test func reviewedRolesKeepAnExceptionalHydroGoblet() throws {
    let goblet = try Artifact(
      setName: "Golden Troupe", slot: .goblet, main: .hydroDamage, level: 20,
      substats: [
        Substat(.hpPercent, 17.49), Substat(.critRate, 11.67), Substat(.critDamage, 15.54),
        Substat(.energyRecharge, 6.48),
      ])
    let matches = CharacterAssessment.evaluate(goblet)
    let verdict = VerdictEngine.evaluate(goblet, matches: matches, inventory: [])
    #expect(verdict.kind == .keep)
    #expect(["furina", "neuvillette", "yelan"].contains(verdict.characterID ?? ""))
  }
}
