import Foundation
import Testing

@testable import LoupeCore

struct VerdictTests {
  /// Test-only roles with controlled stats, so expectations do not depend on reviewed data. They
  /// run the "Test" set unless `fit` says otherwise; nil makes every piece an off-piece.
  private static func role(
    _ id: String, useful: [Stat], secondary: [Stat] = [], fit: CharacterSetFit? = .preferred
  ) -> CharacterRole {
    CharacterRole(
      characterID: id, characterName: id.capitalized, roleID: id + ".synthetic",
      roleName: "Synthetic verdict test",
      mains: [
        .flower: [.hp], .plume: [.atk], .sands: [.elementalMastery], .goblet: [.pyroDamage],
        .circlet: [.critRate],
      ],
      usefulStats: useful, secondaryStats: secondary,
      sets: fit.map { [RoleSet("Test", $0, "Synthetic set.")] } ?? [], conditions: [],
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
    cr: Int = 0, cd: Int = 0, atk: Int = 0, er: Int = 0, level: Int = 20, set: String = "Test"
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
      setName: set, slot: .plume, main: .atk, level: level,
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

  @Test func aSupportsGradeLevelsAFlowerOnlyAtS() throws {
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
    #expect(verdict.reason == "A for a support; supports level flowers only at S")
    // Off-set, that A is below the bar, so the crit role's D is named and scoped.
    let offSet = Self.role(
      "support", useful: [.elementalMastery], secondary: [.energyRecharge], fit: nil)
    let scoped = Self.verdict(em, [Self.crit, offSet])
    #expect(scoped.kind == .fodder)
    #expect(scoped.characterID == "crit")
    #expect(scoped.reason == "D for on-set and damage roles; off-set flowers need S")
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
    #expect(review.reason.hasSuffix("for a support · no saved +20 Test HP flowers to compare yet"))
  }

  @Test func aSupportsAOrBLevelsASandsWhileFewAreSaved() throws {
    // ER and ATK% on an EM sands: A for an ER support, D for an ATK crit role.
    let sands = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 0,
      substats: [
        Substat(.energyRecharge, 6.48), Substat(.atkPercent, 5.83), Substat(.def, 23.15),
        Substat(.hp, 298.75),
      ])
    let support = Self.role("support", useful: [.energyRecharge], secondary: [.atkPercent])
    let level = Self.verdict(sands, [Self.crit, support])
    #expect(level.grade == .a)
    #expect(level.title == "Level to +4")
    #expect(level.characterID == "support")
    #expect(level.reason == "A for a support · 0 saved Test Elemental Mastery sands")
    // One weaker saved sands fills the pool of a lone support.
    let weaker = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 20,
      substats: [
        Substat(.energyRecharge, 6.48), Substat(.def, 138.9), Substat(.hp, 298.75),
        Substat(.atk, 19.45),
      ])
    let full = Self.verdict(sands, [Self.crit, support], inventory: [weaker])
    #expect(full.standings["support.synthetic"] == .open)
    #expect(full.kind == .fodder)
    #expect(full.reason == "A for a support; 1 saved Test Elemental Mastery sands is enough")
    // A B levels too, but a main-stat gap ranks above it and gives the reason.
    let low = try Artifact(
      setName: "Test", slot: .sands, main: .elementalMastery, level: 0,
      substats: [
        Substat(.energyRecharge, 4.53), Substat(.critRate, 2.72), Substat(.def, 16.2),
        Substat(.hp, 209.13),
      ])
    let b = Self.verdict(low, [support])
    #expect(b.grade == .b)
    #expect(b.title == "Level to +4")
    #expect(b.reason == "B for a support · 0 saved Test Elemental Mastery sands")
    let em = Self.role("em", useful: [.elementalMastery])
    let gap = Self.verdict(low, [support, em])
    #expect(gap.characterID == "em")
    #expect(gap.reason == "Main stat fills a gap: 0 saved Test Elemental Mastery sands")
  }

  @Test func aThinButScannedPoolRescuesACGoblet() throws {
    let oneCrit = try Artifact(
      setName: "Test", slot: .goblet, main: .pyroDamage, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.def, 16.2)],
      unactivated: Substat(.elementalMastery, 16.32))
    let twin = Self.role(
      "twin", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])
    let weak = try Artifact(
      setName: "Test", slot: .goblet, main: .pyroDamage, level: 20,
      substats: [
        Substat(.critRate, 3.89), Substat(.hp, 298.75 * 6), Substat(.def, 23.15),
        Substat(.elementalMastery, 16.32),
      ])
    let level = Self.verdict(oneCrit, [Self.crit, twin], inventory: [weak])
    #expect(level.grade == .c)
    #expect(level.title == "Level to +4")
    #expect(level.reason == "C · only 1 saved Test Pyro Dmg Bonus goblet")
    // An empty pool usually means an unscanned bag.
    #expect(Self.verdict(oneCrit, [Self.crit, twin]).kind == .fodder)
  }

  @Test func aThinPoolRescuesNoCFlowerOrPlume() throws {
    // Every flower and plume shares one main stat, so a thin pool of them soon fills.
    let twin = Self.role(
      "twin", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])
    let plume = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.def, 16.2)],
      unactivated: Substat(.elementalMastery, 16.32))
    let unfinished = Self.verdict(plume, [Self.crit, twin], inventory: [try Self.plume(cr: 1)])
    #expect(unfinished.grade == .c)
    #expect(unfinished.kind == .fodder)
    #expect(unfinished.reason == "C at best for every role")
    let flower = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.def, 16.2), Substat(.elementalMastery, 16.32)],
      unactivated: Substat(.defPercent, 5.1))
    let weakFlower = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.critRate, 3.89), Substat(.def, 138.9), Substat(.elementalMastery, 16.32),
        Substat(.defPercent, 5.1),
      ])
    let flowerVerdict = Self.verdict(flower, [Self.crit, twin], inventory: [weakFlower])
    #expect(flowerVerdict.grade == .c)
    #expect(flowerVerdict.kind == .fodder)
    #expect(flowerVerdict.reason == "C at best for every role")
    // Finished, the same thin pool asks for no review.
    let finished = try Self.plume(cr: 2)
    let review = Self.verdict(finished, [Self.crit, twin], inventory: [try Self.plume(cr: 1)])
    #expect(review.grade == .c)
    #expect(review.kind == .fodder)
    #expect(review.reason == "C at best for every role")
  }

  @Test func anyThinCRoleRescuesAFinishedPiece() throws {
    // C for an HP healer, nothing for an ATK crit role: one weaker saved circlet leaves room.
    let circlet = try Artifact(
      setName: "Test", slot: .circlet, main: .healing, level: 20,
      substats: [
        Substat(.hpPercent, 9.33), Substat(.critRate, 3.89), Substat(.critDamage, 38.85),
        Substat(.def, 23.15),
      ])
    let weaker = try Artifact(
      setName: "Test", slot: .circlet, main: .healing, level: 20,
      substats: [
        Substat(.def, 138.9), Substat(.atk, 19.45), Substat(.hp, 298.75),
        Substat(.energyRecharge, 6.48),
      ])
    let healers = CharacterRoles.all.filter { $0.mains[.circlet]?.contains(.healing) == true }
    let matches = CharacterAssessment.evaluate(circlet, roles: healers)
    #expect(matches.contains { $0.grades?.grade == .c && $0.usefulStats == [.hpPercent] })
    let verdict = VerdictEngine.evaluate(circlet, matches: matches, inventory: [weaker])
    #expect(verdict.kind == .review)
    #expect(verdict.reason == "C · only 1 saved Healing Bonus circlet")
  }

  @Test func savedPiecesBeyondTheBestOutcomeMakeItFodder() throws {
    let starter = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 2.72), Substat(.hp, 209.13), Substat(.atkPercent, 4.08)],
      unactivated: Substat(.def, 16.2))
    let strong = try Self.plume(cr: 3, cd: 3, atk: 2)
    let verdict = Self.verdict(starter, inventory: [strong])
    #expect(verdict.kind == .fodder)
    #expect(verdict.reason == "Enough saved Test ATK plumes beat its best outcome for every role")
    // The candidate's own saved record is not a comparison.
    let own = Self.verdict(starter, inventory: [strong], excluding: strong.id)
    #expect(own.kind == .level)
  }

  @Test func aCoveredUnfinishedAIsKeptAsASpare() throws {
    let doubleCrit = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atkPercent, 5.3), Substat(.critDamage, 7.8)],
      unactivated: Substat(.hp, 269))
    let strong = try Self.plume(cr: 4, cd: 3, atk: 1)
    let spare = Self.verdict(doubleCrit, inventory: [strong])
    #expect(spare.standings == ["crit.synthetic": .covered(1)])
    #expect(spare.kind == .keep)
    #expect(spare.grade == .a)
    #expect(spare.reason == "A · spare; 1 saved Test ATK plume beats its best outcome")
    // With nothing saved a role is never covered, whatever the policy.
    var none = VerdictPolicy()
    none.maxBackups = 0
    let open = Self.verdict(doubleCrit, policy: none)
    #expect(open.standings == ["crit.synthetic": .open])
    #expect(open.title == "Level to +4")
  }

  @Test func aSpareIsKeptForItsOnSetRoleNotAnOffSetOne() throws {
    let useful: [Stat] = [.atkPercent, .critRate, .critDamage]
    let offPiece = Self.role("off", useful: useful, secondary: [.energyRecharge], fit: nil)
    let piece = try Self.plume(cr: 3, cd: 1)
    let strong = try Self.plume(cr: 4, cd: 3, atk: 1)
    let spare = Self.verdict(piece, [offPiece, Self.crit], inventory: [strong])
    #expect(
      spare.standings == ["off.synthetic": .offSetBelowBar(.s), "crit.synthetic": .covered(1)])
    #expect(spare.kind == .keep)
    #expect(spare.characterID == "crit")
    #expect(spare.reason == "A · spare; 1 saved Test ATK plume scores higher")
  }

  @Test func finishedSAndAAreKeptWithTheirReplacementOdds() throws {
    let s = Self.verdict(try Self.plume(cr: 4, cd: 3, atk: 1))
    #expect(s.kind == .keep)
    #expect(s.grade == .s)
    #expect(s.reason.hasPrefix("S · "))
    let a = Self.verdict(try Self.plume(cr: 3, cd: 1))
    #expect(a.kind == .keep)
    #expect(a.grade == .a)
    #expect(a.reason.hasPrefix("A · ~"))
    #expect(a.reason.hasSuffix(" of resin to replace"))
  }

  @Test func finishedBDependsOnTheSavedPool() throws {
    let piece = try Self.plume(cr: 2, atk: 1)
    let empty = Self.verdict(piece)
    #expect(empty.kind == .review)
    #expect(empty.grade == .b)
    #expect(empty.reason == "B · no saved +20 Test ATK plumes to compare yet")
    let weaker = try Self.plume(cr: 1)
    let stronger = try Self.plume(cr: 3, cd: 1)
    #expect(
      Self.verdict(piece, inventory: [weaker]).reason == "B · beats the 1 saved Test ATK plume")
    #expect(
      Self.verdict(piece, inventory: [try piece.withID(UUID())]).reason
        == "B · tied with the 1 saved Test ATK plume")
    // Saved pieces never make an A fodder, but a covered B can still be.
    let fodder = Self.verdict(piece, inventory: [stronger])
    #expect(fodder.kind == .fodder)
    #expect(fodder.reason == "Enough saved Test ATK plumes beat it for every role")
    // Beside a role that grades it lower, the covered B gives the reason.
    let em = Self.role("em", useful: [.elementalMastery])
    let mixed = Self.verdict(piece, [Self.crit, em], inventory: [stronger])
    #expect(mixed.kind == .fodder)
    #expect(mixed.characterID == "crit")
    #expect(mixed.reason == "B · 1 saved Test ATK plume beats it")
  }

  @Test func rolesSharingAProfileShareTheirBackups() throws {
    let piece = try Self.plume(cr: 2, atk: 1)
    let stronger = try Self.plume(cr: 3, cd: 1)
    let twin = Self.role(
      "twin", useful: [.atkPercent, .critRate, .critDamage], secondary: [.energyRecharge])
    let pair = Self.verdict(piece, [Self.crit, twin], inventory: [stronger])
    #expect(pair.kind == .keep)
    #expect(pair.reason == "B · #2 of saved Test ATK plumes")
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
    #expect(keep.reason == "Main stat fills a gap: 0 saved Test Elemental Mastery sands")
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
    // Set and slot still set aside an off-set plume without a forecast, which has no grade.
    let offPiece = Self.role("off", useful: [.atkPercent, .critRate, .critDamage], fit: nil)
    let mixed = Self.verdict(incomplete, [Self.crit, offPiece])
    #expect(mixed.kind == .review)
    #expect(mixed.standings == ["off.synthetic": .offSetBelowBar(.s)])
  }

  /// A finished Pyro DMG goblet with maximum rolls on the named lines.
  private static func goblet(cr: Int, cd: Int, set: String = "Test") throws -> Artifact {
    try Artifact(
      setName: set, slot: .goblet, main: .pyroDamage, level: 20,
      substats: [
        Substat(.critRate, 3.89 * Double(cr)), Substat(.critDamage, 7.77 * Double(cd)),
        Substat(.hp, 298.75 * Double(8 - cr - cd)), Substat(.def, 23.15),
      ])
  }

  @Test func onSetRolesAreHarderToReplaceThanOffPieces() throws {
    let piece = try Self.goblet(cr: 3, cd: 2)
    let useful: [Stat] = [.atkPercent, .critRate, .critDamage]
    let offPiece = Self.role("off", useful: useful, fit: nil)
    let onSet = Self.role("set", useful: useful)
    // An off-piece can come from any domain, so the same piece is twice as easy to replace.
    #expect(Self.verdict(piece, [onSet]).reason != Self.verdict(piece, [offPiece]).reason)
    // A preferred set breaks a tie between equal letters.
    #expect(Self.verdict(piece, [offPiece, onSet]).characterID == "set")
  }

  @Test func onSetRolesCompareOnlyWithSavedPiecesOfTheirSet() throws {
    // The user's report: an Obsidian Codex flower whose crit roles were set aside by saved
    // flowers of other sets, which a four-piece Codex build would never wear.
    let piece = try Self.plume(cr: 3, cd: 1)
    let others = try (0..<3).map { _ in try Self.plume(cr: 4, cd: 3, set: "Other") }
    let onSet = Self.verdict(piece, inventory: others)
    #expect(onSet.kind == .keep)
    #expect(onSet.grade == .a)
    #expect(onSet.standings == ["crit.synthetic": .open])
    // Saved pieces of its own set still cover it, but they never make an A fodder.
    let own = try (0..<3).map { _ in try Self.plume(cr: 4, cd: 3) }
    let covered = Self.verdict(piece, inventory: own)
    #expect(covered.standings == ["crit.synthetic": .covered(3)])
    #expect(covered.kind == .keep)
    #expect(covered.grade == .a)
    #expect(covered.reason == "A · spare; 3 saved Test ATK plumes score higher")
  }

  @Test func offSetFlowersAndPlumesCountAtAHigherBar() throws {
    let useful: [Stat] = [.atkPercent, .critRate, .critDamage]
    let offPiece = Self.role("off", useful: useful, secondary: [.energyRecharge], fit: nil)
    // Finished, only S counts, and it keeps the piece.
    let finishedS = Self.verdict(try Self.plume(cr: 4, cd: 3, atk: 1), [offPiece])
    #expect(finishedS.grade == .s)
    #expect(finishedS.kind == .keep)
    #expect(finishedS.standings == ["off.synthetic": .open])
    #expect(finishedS.reason.hasPrefix("S off-set · "))
    let finishedA = Self.verdict(try Self.plume(cr: 3, cd: 1), [offPiece])
    #expect(finishedA.kind == .fodder)
    #expect(finishedA.standings == ["off.synthetic": .offSetBelowBar(.s)])
    #expect(finishedA.reason == "A as an off-set plume; needs S")
    // With the finished bar at A, an A keeps the piece and a B does not.
    var lower = VerdictPolicy()
    lower.offSetFinishedBar = .a
    let a = Self.verdict(try Self.plume(cr: 3, cd: 1), [offPiece], policy: lower)
    #expect(a.grade == .a)
    #expect(a.kind == .keep)
    #expect(a.standings == ["off.synthetic": .open])
    #expect(a.reason.hasPrefix("A off-set · "))
    let b = Self.verdict(try Self.plume(cr: 2, atk: 1), [offPiece], policy: lower)
    #expect(b.kind == .fodder)
    #expect(b.standings == ["off.synthetic": .offSetBelowBar(.a)])
    #expect(b.reason == "B as an off-set plume; needs A or better")
    // Unfinished, only S counts, and it levels to +20.
    let perfect = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [
        Substat(.critRate, 2.72), Substat(.atkPercent, 4.08), Substat(.critDamage, 5.44),
        Substat(.energyRecharge, 4.53),
      ])
    let s = Self.verdict(perfect, [offPiece])
    #expect(s.title == "Level to +20")
    #expect(s.reason == "S off-set · could be one of your best")
    let doubleCrit = try Artifact(
      setName: "Test", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atkPercent, 5.3), Substat(.critDamage, 7.8)],
      unactivated: Substat(.hp, 269))
    let unfinishedA = Self.verdict(doubleCrit, [offPiece])
    #expect(unfinishedA.kind == .fodder)
    #expect(unfinishedA.standings == ["off.synthetic": .offSetBelowBar(.s)])
    #expect(unfinishedA.reason == "A as an off-set plume; needs S")
    // The bars are policy.
    var policy = VerdictPolicy()
    policy.offSetUnfinishedBar = .a
    #expect(Self.verdict(doubleCrit, [offPiece], policy: policy).title == "Level to +4")
    // The on-set role leads, though the off-piece grades the same and clears its bar.
    let onSet = Self.role("set", useful: useful)
    #expect(
      Self.verdict(try Self.plume(cr: 3, cd: 1), [offPiece, onSet], policy: lower).characterID
        == "set")
  }

  @Test func anOffSetPlumeBelowTheBarFillsNoGap() throws {
    // A flat-ATK role fits a plume by main stat only.
    let flat = Self.role("flat", useful: [.atk])
    let offFlat = Self.role("offflat", useful: [.atk], fit: nil)
    let piece = try Self.plume(cr: 1)
    #expect(Self.verdict(piece, [flat]).reason == "Main stat fills a gap: 0 saved Test ATK plumes")
    let gap = Self.verdict(piece, [offFlat])
    #expect(gap.kind == .fodder)
    #expect(gap.standings == ["offflat.synthetic": .offSetBelowBar(.s)])
    #expect(gap.reason == "Off-set plumes count only at S")
  }

  @Test func offPiecesRankByHowOftenTheirSlotIsTheOffPiece() throws {
    let useful: [Stat] = [.atkPercent, .critRate, .critDamage]
    let offPiece = Self.role("off", useful: useful, fit: nil)
    let alternative = Self.role("alt", useful: useful, fit: .alternative)
    let preferred = Self.role("set", useful: useful)
    // An off-set goblet is the usual 4+1 off-piece, so it ranks with an alternative set.
    let goblet = try Self.goblet(cr: 3, cd: 2)
    let gobletMatches = CharacterAssessment.evaluate(
      goblet, roles: [offPiece, alternative, preferred])
    #expect(gobletMatches.map(\.characterID) == ["alt", "off", "set"])
    #expect(gobletMatches.map { $0.wearRank(.goblet) } == [2, 2, 3])
    // An off-set circlet ranks below an alternative set, a flower or plume below that.
    let off = try #require(gobletMatches.first { $0.characterID == "off" })
    #expect(off.wearRank(.circlet) == 1)
    #expect(off.wearRank(.sands) == 1)
    #expect(off.wearRank(.flower) == 0)
    #expect(off.isRareOffPiece(.plume))
    #expect(!off.isRareOffPiece(.goblet))
  }

  @Test func aCodexFlowerGoesToACodexRunnerNotAnOffSetSupport() throws {
    // The user's report: crit flowers of other sets set aside every Codex role, so an off-set
    // DEF support's B drove the verdict.
    func flower(_ set: String, _ lines: [(Stat, Double)]) throws -> Artifact {
      try Artifact(
        setName: set, slot: .flower, main: .hp, level: 20,
        substats: lines.map { Substat($0.0, $0.1) })
    }
    let piece = try flower(
      "Obsidian Codex",
      [(.critRate, 7.8), (.critDamage, 5.4), (.atkPercent, 9.9), (.defPercent, 17.5)])
    let saved = try [
      flower(
        "Blizzard Strayer",
        [(.energyRecharge, 4.5), (.atk, 14), (.critRate, 10.9), (.critDamage, 18.7)]),
      flower(
        "Golden Troupe",
        [(.critDamage, 26.4), (.critRate, 7.4), (.energyRecharge, 5.8), (.atkPercent, 4.1)]),
      flower(
        "Heart of the Furnace",
        [(.atk, 19), (.critRate, 8.9), (.atkPercent, 11.1), (.critDamage, 21)]),
      flower(
        "Silken Moon's Serenade",
        [(.atk, 29), (.critDamage, 15.5), (.critRate, 8.6), (.energyRecharge, 11)]),
      flower(
        "Obsidian Codex",
        [(.critRate, 6.6), (.critDamage, 23.3), (.defPercent, 6.6), (.atkPercent, 5.3)]),
    ]
    let matches = CharacterAssessment.evaluate(piece, inventory: saved)
    let verdict = VerdictEngine.evaluate(piece, matches: matches, inventory: saved)
    let lead = try #require(matches.first { $0.roleID == verdict.roleID })
    #expect(lead.setFit == .preferred)
    #expect(verdict.kind == .keep)
    func standing(_ id: String) throws -> RoleStanding? {
      verdict.standings[try #require(matches.first { $0.characterID == id }).roleID]
    }
    #expect(try standing("gorou") == .offSetBelowBar(.s))
    // Off-set Itto grades it below S too.
    #expect(try standing("itto") == .offSetBelowBar(.s))
    #expect(try standing("chasca") == .open)
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
