import Foundation
import Testing

@testable import LoupeCore

struct VerdictTests {
  /// Test-only roles with controlled stats, so expectations do not depend on reviewed data.
  private static func role(
    _ id: String, useful: [Stat], secondary: [Stat] = [], preferred: Bool = false
  ) -> CharacterRole {
    CharacterRole(
      characterID: id, characterName: id.capitalized, roleID: id + ".synthetic",
      roleName: "Synthetic verdict test",
      mains: [.flower: [.hp], .plume: [.atk], .sands: [.elementalMastery]],
      usefulStats: useful, secondaryStats: secondary,
      sets: preferred ? [RoleSet("Test", .preferred, "Synthetic set.")] : [], conditions: [],
      source: RoleSource(
        url: "https://example.invalid/synthetic", section: "Synthetic test only",
        sourceVersion: "test", reviewedOn: "2026-10-26"))
  }

  private static let crit = role(
    "crit", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])

  private static func verdict(
    _ piece: Artifact, _ roles: [CharacterRole] = [crit], inventory: [Artifact] = [],
    excluding: UUID? = nil, policy: VerdictPolicy = .standard
  ) -> Verdict {
    VerdictEngine.evaluate(
      piece, matches: CharacterAssessment.evaluate(piece, roles: roles), inventory: inventory,
      excluding: excluding, policy: policy)
  }

  /// An ATK plume from a four-line start, with maximum rolls on the named lines. Useless lines
  /// take the remaining rolls.
  private static func plume(
    cr: Int = 0, cd: Int = 0, atk: Int = 0, er: Int = 0, level: Int = 20
  ) throws -> Artifact {
    let useful = [
      (Stat.critRate, cr), (.critDamage, cd), (.atkPercent, atk), (.energyRecharge, er),
    ]
    .filter { $0.1 > 0 }
    let junk = Array([Stat.hp, .def, .elementalMastery, .hpPercent].prefix(4 - useful.count))
    var left = 4 + level / 4 - useful.reduce(0) { $0 + $1.1 } - junk.count
    let counts = junk.map { _ in
      let extra = min(5, left)
      left -= extra
      return 1 + extra
    }
    let lines = useful + zip(junk, counts).map { ($0, $1) }
    return try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: level,
      substats: lines.map { Substat($0.0, $0.0.rolls.last! * Double($0.1)) })
  }

  @Test func noMatchingRoleIsFodder() throws {
    let verdict = VerdictEngine.evaluate(try Self.plume(cr: 6), matches: [], inventory: [])
    #expect(verdict.kind == .fodder)
    #expect(verdict.reason == "No character role uses ATK plumes")
  }

  @Test func unfinishedLettersDecideHowFarToLevel() throws {
    // The plume from the user's report: double crit and ATK%, HP at +4.
    let doubleCrit = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atkPercent, 5.3), Substat(.critDamage, 7.8)],
      unactivated: Substat(.hp, 269))
    // A levels a checkpoint at a time, so the grade is read again as rolls land.
    let a = Self.verdict(doubleCrit)
    #expect(a.kind == .level)
    #expect(a.targetLevel == 4)
    #expect(a.grade == .a)
    #expect(a.summary == "Crit · A · worth rolling")
    #expect((a.chanceOfAOrBetter ?? 0) > 0.99)

    let perfect = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [
        Substat(.critRate, 2.72), Substat(.atkPercent, 4.08), Substat(.critDamage, 5.44),
        Substat(.energyRecharge, 4.53),
      ])
    let s = Self.verdict(perfect)
    #expect(s.title == "Level to +20")
    #expect(s.reason == "S · could be one of your best")

    let critAndAtk = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.atkPercent, 4.08)],
      unactivated: Substat(.def, 16.2))
    let b = Self.verdict(critAndAtk)
    #expect(b.title == "Level to +4")
    #expect(b.reason == "B · look again at +4")

    let oneCrit = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.def, 16.2)],
      unactivated: Substat(.elementalMastery, 16.32))
    let c = Self.verdict(oneCrit)
    #expect(c.kind == .fodder)
    #expect(c.reason == "C at best for every role")

    let junk = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.hp, 209.13), Substat(.def, 16.2), Substat(.elementalMastery, 16.32)],
      unactivated: Substat(.hpPercent, 4.08))
    #expect(Self.verdict(junk).reason == "D for every role")
  }

  @Test func aSupportsGradeLevelsOnlyAtS() throws {
    // EM and ER on a four-line start: A for an EM support, D for an ATK crit role.
    let em = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [
        Substat(.elementalMastery, 23.31), Substat(.energyRecharge, 6.48), Substat(.def, 23.15),
        Substat(.atk, 19.45),
      ])
    let support = Self.role("support", useful: [.elementalMastery], secondary: [.energyRecharge])
    let verdict = Self.verdict(em, [Self.crit, support])
    #expect(verdict.kind == .fodder)
    #expect(verdict.characterID == "support")
    #expect(verdict.reason == "A for a support; supports level only at S")
    // Finished, the same support grade asks for a comparison rather than discarding it.
    let finished = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.elementalMastery, 69.93), Substat(.energyRecharge, 12.96), Substat(.def, 69.45),
        Substat(.atk, 19.45),
      ])
    let review = Self.verdict(finished, [Self.crit, support])
    #expect(review.grade == .a)
    #expect(review.kind == .review)
    #expect(review.reason.hasSuffix("for a support · no saved +20 HP flowers to compare yet"))
  }

  @Test func aThinButScannedPoolRescuesACPiece() throws {
    let oneCrit = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.def, 16.2)],
      unactivated: Substat(.elementalMastery, 16.32))
    let twin = Self.role(
      "twin", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])
    let weak = try Self.plume(cr: 1)
    let level = Self.verdict(oneCrit, [Self.crit, twin], inventory: [weak])
    #expect(level.title == "Level to +4")
    #expect(level.reason == "C · only 1 saved ATK plumes")
    // An empty pool usually means an unscanned bag.
    #expect(Self.verdict(oneCrit, [Self.crit, twin]).kind == .fodder)
  }

  @Test func savedPiecesBeyondTheBestOutcomeMakeItFodder() throws {
    let starter = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.atkPercent, 4.08)],
      unactivated: Substat(.def, 16.2))
    let strong = try Self.plume(cr: 3, cd: 3, atk: 2)
    let verdict = Self.verdict(starter, inventory: [strong])
    #expect(verdict.kind == .fodder)
    #expect(verdict.reason == "Enough saved ATK plumes beat its best outcome for every role")
    // The candidate's own saved record is not a comparison.
    let own = Self.verdict(starter, inventory: [strong], excluding: strong.id)
    #expect(own.kind == .level)
  }

  @Test func finishedSAndAAreKeptWithTheirReplacementOdds() throws {
    let s = Self.verdict(try Self.plume(cr: 4, cd: 3, atk: 1))
    #expect(s.kind == .keep)
    #expect(s.grade == .s)
    #expect(s.reason.hasPrefix("S · "))
    let a = Self.verdict(try Self.plume(cr: 3, cd: 1))
    #expect(a.kind == .keep)
    #expect(a.grade == .a)
    #expect(a.reason.hasPrefix("A · about "))
    #expect(a.reason.hasSuffix(" drops to replace"))
  }

  @Test func finishedBDependsOnTheSavedPool() throws {
    let piece = try Self.plume(cr: 2, atk: 1)
    let empty = Self.verdict(piece)
    #expect(empty.kind == .review)
    #expect(empty.grade == .b)
    #expect(empty.reason == "B · no saved +20 ATK plumes to compare yet")
    let weaker = try Self.plume(cr: 1)
    let stronger = try Self.plume(cr: 3, cd: 1)
    #expect(Self.verdict(piece, inventory: [weaker]).reason == "B · beats all 1 saved ATK plumes")
    #expect(
      Self.verdict(piece, inventory: [try piece.withID(UUID())]).reason
        == "B · tied for best of 1 saved ATK plumes")
    let fodder = Self.verdict(piece, inventory: [stronger])
    #expect(fodder.kind == .fodder)
    #expect(fodder.reason == "Enough saved ATK plumes beat it for every role")
  }

  @Test func rolesSharingAProfileShareTheirBackups() throws {
    let piece = try Self.plume(cr: 2, atk: 1)
    let stronger = try Self.plume(cr: 3, cd: 1)
    let twin = Self.role(
      "twin", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])
    let pair = Self.verdict(piece, [Self.crit, twin], inventory: [stronger])
    #expect(pair.kind == .keep)
    #expect(pair.reason == "B · #2 of saved ATK plumes")
    var policy = VerdictPolicy()
    policy.maxBackups = 1
    let capped = Self.verdict(piece, [Self.crit, twin], inventory: [stronger], policy: policy)
    #expect(capped.kind == .fodder)
  }

  @Test func mainStatOnlyFitsKeepUntilTheSavedPoolHasRoom() throws {
    let sands = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 20,
      substats: [
        Substat(.atk, 58.35), Substat(.def, 46.30), Substat(.hp, 597.50),
        Substat(.critRate, 3.89),
      ])
    let em = Self.role("em", useful: [.elementalMastery])
    let keep = Self.verdict(sands, [em])
    #expect(keep.kind == .keep)
    #expect(keep.grade == nil)
    #expect(keep.reason == "Main stat fills a gap: 0 saved Elemental Mastery sands")
    let covered = Self.verdict(sands, [em], inventory: [try sands.withID(UUID())])
    #expect(covered.kind == .fodder)
    #expect(covered.reason == "Main-stat fit only; saved pieces already cover it")
  }

  @Test func piecesWithoutAForecastAskForReview() throws {
    let incomplete = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 3.89), Substat(.hp, 298.75), Substat(.def, 23.15)])
    let verdict = Self.verdict(incomplete)
    #expect(verdict.kind == .review)
    #expect(verdict.reason.contains("fourth stat"))
    #expect(verdict.chanceOfAOrBetter == nil)
  }

  @Test func onSetRolesAreHarderToReplaceThanOffPieces() throws {
    let piece = try Self.plume(cr: 3, cd: 1)
    let onSet = Self.role(
      "set", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge],
      preferred: true)
    // An off-piece can come from any domain, so the same piece is twice as easy to replace.
    #expect(Self.verdict(piece, [onSet]).reason != Self.verdict(piece).reason)
    // A preferred set breaks a tie between equal letters.
    #expect(Self.verdict(piece, [Self.crit, onSet]).characterID == "set")
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
