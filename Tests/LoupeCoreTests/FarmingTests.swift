import Foundation
import Testing

@testable import LoupeCore

struct FarmingTests {
  static func role(_ id: String) -> CharacterRole {
    CharacterRoles.all.first { $0.roleID == id }!
  }
  static let furina = role("furina.off-field-hp")
  static let kazuha = role("kazuha.em-swirl-support")

  /// Nine top rolls on a four-line start: three CRIT Rate, three CRIT DMG, two HP%, one flat ATK.
  static func strongFlower(_ set: String) throws -> Artifact {
    try Artifact(
      setName: set, slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 23.31), Substat(.hpPercent, 11.66),
        Substat(.atk, 19.45),
      ])
  }

  /// The same rolls on a plume, with flat HP for flat ATK.
  static func strongPlume(_ set: String) throws -> Artifact {
    try Artifact(
      setName: set, slot: .plume, main: .atk, level: 20,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 23.31), Substat(.hpPercent, 11.66),
        Substat(.hp, 298.75),
      ])
  }

  /// Nine top rolls on lines Furina doesn't value.
  static func weakFlower(_ set: String) throws -> Artifact {
    try Artifact(
      setName: set, slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.atk, 77.8), Substat(.def, 46.3), Substat(.defPercent, 14.58),
        Substat(.elementalMastery, 23.31),
      ])
  }

  static func plan(_ roles: [CharacterRole], _ inventory: [Artifact] = []) -> FarmingPlan.Result {
    FarmingPlan.evaluate(roles: roles.map { ($0, 1) }, inventory: inventory)
  }

  static func slot(_ role: CharacterRole, _ slot: Slot, _ inventory: [Artifact] = [])
    -> FarmingNeed?
  {
    FarmingPlan.character(role, inventory: inventory).slots.first { $0.slot == slot }
  }

  @Test func everyDomainDropsTwoSetsNoOtherDomainDoes() {
    let keys = ArtifactDomain.all.flatMap(\.sets).map(Artifact.normalizeSet)
    #expect(ArtifactDomain.all.allSatisfy { Set($0.sets).count == 2 })
    #expect(Set(keys).count == keys.count)
    #expect(ArtifactDomain.bossSets.allSatisfy { ArtifactDomain.dropping($0) == nil })
  }

  /// A role set missing from the table would quietly drop out of every plan.
  @Test func everyRoleSetIsFarmableOrFourStarOnly() {
    let fourStarOnly = ["Instructor", "The Exile"].map(Artifact.normalizeSet)
    let unknown = Set(
      CharacterRoles.all.flatMap(\.sets).map(\.name).filter {
        !ArtifactDomain.isFiveStar($0) && !fourStarOnly.contains(Artifact.normalizeSet($0))
      })
    #expect(unknown.isEmpty, "\(unknown.sorted())")
    #expect(CharacterRoles.all.allSatisfy { FarmingPlan.set(for: $0) != nil })
  }

  @Test func anEmptyInventoryWantsEverySlotOfTheRolesSet() throws {
    let build = FarmingPlan.character(Self.furina, inventory: [])
    #expect(build.set == "Golden Troupe")
    #expect(build.domain?.name == "Denouement of Sin")
    #expect(build.slots.map(\.slot) == Slot.allCases)
    #expect(build.slots.allSatisfy { $0.best == nil && !$0.offSet && $0.chancePerDrop > 0 })
    #expect(build.offSetSlot == nil)
    // A flower is always HP, so its chance is the set, the slot, and the share finishing A.
    let flower = try #require(build.slots.first)
    let share = flower.chancePerDrop / (0.5 / 5)
    #expect(share > 0.1 && share < 0.35)

    let plan = Self.plan([Self.furina])
    let top = try #require(plan.domains.first)
    #expect(plan.domains.count == 1)
    #expect(top.domain.name == "Denouement of Sin")
    #expect(abs(top.upgradesPerDrop - build.upgradesPerDrop) < 1e-12)
  }

  @Test func aStrongSavedPieceLeavesLessToGain() throws {
    let empty = try #require(Self.slot(Self.furina, .flower))
    let weak = try #require(Self.slot(Self.furina, .flower, [Self.weakFlower("Golden Troupe")]))
    let strong = try #require(
      Self.slot(Self.furina, .flower, [Self.strongFlower("Golden Troupe")]))
    // A piece below the A cutoff raises no bar: an upgrade still has to reach A.
    #expect(abs(weak.chancePerDrop - empty.chancePerDrop) < 1e-12)
    #expect(weak.bestGrade == .d && !weak.isReady)
    #expect(strong.chancePerDrop < empty.chancePerDrop / 10)
    #expect(strong.bestGrade == .s && strong.isReady)
  }

  @Test func oneOffSetPieceStandsInForTheSet() throws {
    let pieces = [
      try Self.strongFlower("Emblem of Severed Fate"),
      try Self.strongPlume("Emblem of Severed Fate"),
    ]
    let build = FarmingPlan.character(Self.furina, inventory: pieces)
    // A 4+1 build wears one off-set piece, in the slot it helps most.
    #expect(build.slots.filter(\.offSet).count == 1)
    let off = try #require(build.slots.first { $0.offSet })
    #expect(off.best?.setName != "Golden Troupe")
    #expect(off.chancePerDrop < (Self.slot(Self.furina, off.slot)?.chancePerDrop ?? 0) / 10)
    // The other Emblem piece isn't worn: the set's own slot there is empty.
    let other = try #require(
      build.slots.first { [.flower, .plume].contains($0.slot) && $0.slot != off.slot })
    #expect(other.best == nil && !other.offSet)
  }

  @Test func theSetsOwnBetterPieceKeepsItsSlot() throws {
    let build = FarmingPlan.character(
      Self.furina,
      inventory: [
        try Self.strongFlower("Golden Troupe"), try Self.weakFlower("Emblem of Severed Fate"),
      ])
    #expect(build.offSetSlot == nil)
    #expect(build.slots.first?.best?.setName == "Golden Troupe")
  }

  /// Another set's piece rarer among its own main's drops still has to outscore the set's piece.
  @Test func anOffSetPieceMustBeatTheSetsOwnByScore() throws {
    let hydro = try Artifact(
      setName: "Golden Troupe", slot: .goblet, main: .hydroDamage, level: 20,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 23.31), Substat(.hpPercent, 11.66),
        Substat(.atk, 19.45),
      ])
    let health = try Artifact(
      setName: "Emblem of Severed Fate", slot: .goblet, main: .hpPercent, level: 20,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 23.31), Substat(.energyRecharge, 12.96),
        Substat(.atk, 19.45),
      ])
    let profile = Self.furina.profile
    #expect(profile.score(health.substats) < profile.score(hydro.substats))
    let build = FarmingPlan.character(Self.furina, inventory: [hydro, health])
    let goblet = try #require(build.slots.first { $0.slot == .goblet })
    #expect(!goblet.offSet && goblet.best?.id == hydro.id)
  }

  @Test func defaultRolesFollowTheRostersOrder() {
    // Venti's roster lists EM before ATK crit, though "atk-crit" sorts first.
    #expect(OwnedCharacter.defaultRole(for: "venti")?.roleID == "venti.em")
    #expect(OwnedCharacter.roles(for: "venti").map(\.roleID) == ["venti.em", "venti.atk-crit"])
    // A reviewed role stands in for the archetype it matches.
    #expect(OwnedCharacter.defaultRole(for: "raiden-shogun")?.roleID == "raiden-shogun.hyperbloom")
    #expect(FarmingPlan.roles(owned: []).contains { $0.role.roleID == "venti.em" })
    #expect(OwnedCharacter(characterID: "venti").roleID == "venti.em")
  }

  @Test func aMainStatOnlyFitFillsItsSlot() throws {
    #expect(Self.plan([Self.kazuha]).domains.first?.domain.name == "Valley of Remembrance")
    // EM is Kazuha's only valued stat, so any EM goblet fills the slot.
    let goblet = try #require(Self.slot(Self.kazuha, .goblet))
    #expect(abs(goblet.chancePerDrop - 0.5 / 5 * 10 / 400) < 1e-12)

    let sands = try Artifact(
      setName: "Viridescent Venerer", slot: .sands, main: .elementalMastery, level: 20,
      substats: [
        Substat(.critRate, 11.67), Substat(.critDamage, 23.31), Substat(.hpPercent, 11.66),
        Substat(.atk, 19.45),
      ])
    let filled = try #require(Self.slot(Self.kazuha, .sands, [sands]))
    #expect(filled.isFilled && filled.isReady && filled.bestGrade == nil)
    #expect(Self.slot(Self.kazuha, .sands)?.isFilled == false)
  }

  /// A saved piece of a graded main doesn't stop a main-only fit from beating it.
  @Test func aMainStatOnlyFitBeatsASavedPieceOfAnotherMain() throws {
    let empty = try #require(Self.slot(Self.kazuha, .sands))
    let energy = try Artifact(
      setName: "Viridescent Venerer", slot: .sands, main: .energyRecharge, level: 20,
      substats: [
        Substat(.atk, 77.8), Substat(.def, 46.3), Substat(.defPercent, 14.58),
        Substat(.hp, 298.75),
      ])
    let saved = try #require(Self.slot(Self.kazuha, .sands, [energy]))
    #expect(saved.bestGrade == .d)
    #expect(abs(saved.chancePerDrop - empty.chancePerDrop) < 1e-12)
    #expect(saved.chancePerDrop >= 0.5 / 5 * 30 / 300)
  }

  @Test func domainsRankByUpgradesPerDrop() throws {
    let neuvillette = Self.role("neuvillette.on-field-hp")
    // Neuvillette and Furina share Denouement of Sin; Kazuha alone wants Valley of Remembrance.
    let plan = Self.plan([Self.kazuha, Self.furina, neuvillette])
    #expect(plan.domains.map(\.domain.name) == ["Denouement of Sin", "Valley of Remembrance"])
    let rates = plan.domains.map(\.upgradesPerDrop)
    #expect(rates == rates.sorted(by: >))
    for domain in plan.domains {
      let chances = domain.needs.map(\.chancePerDrop)
      #expect(chances == chances.sorted(by: >))
    }
  }

  @Test func aCharacterBeingBuiltCountsForMoreInTheOrderOnly() throws {
    let even = Self.plan([Self.kazuha, Self.furina])
    let second = try #require(even.domains.last)
    let favoured = try #require(
      even.domains.first.flatMap { first in
        [Self.kazuha, Self.furina].first {
          FarmingPlan.set(for: $0).flatMap(ArtifactDomain.dropping) == second.domain
        }
      })
    let weighted = FarmingPlan.evaluate(
      roles: [Self.kazuha, Self.furina].map { ($0, $0.roleID == favoured.roleID ? 10 : 1) },
      inventory: [])
    #expect(weighted.domains.first?.domain == second.domain)
    #expect(abs((weighted.domains.first?.upgradesPerDrop ?? 0) - second.upgradesPerDrop) < 1e-12)
  }

  @Test func setsReadWeakestFirst() throws {
    let plan = Self.plan(
      [Self.kazuha, Self.furina],
      [
        try Self.strongFlower("Golden Troupe"), try Self.strongPlume("Golden Troupe"),
      ])
    #expect(plan.sets.map(\.set) == ["Viridescent Venerer", "Golden Troupe"])
    let troupe = try #require(plan.sets.last)
    #expect(troupe.readySlots == 2 && troupe.totalSlots == 5)
    #expect(troupe.level == .fair)
    #expect(plan.sets.first?.level == .weak)
  }

  @Test func theAccountCountsOwnedCharactersOrEveryone() {
    let everyone = FarmingPlan.roles(owned: [])
    #expect(Set(everyone.map(\.role.characterID)).count == everyone.count)
    #expect(everyone.count == Set(CharacterRoles.all.map(\.characterID)).count)
    #expect(everyone.allSatisfy { $0.weight == 1 })

    let owned = FarmingPlan.roles(owned: [
      OwnedCharacter(characterID: "furina"),
      OwnedCharacter(characterID: "kazuha", building: true),
    ])
    #expect(owned.map(\.role.roleID) == [Self.furina.roleID, Self.kazuha.roleID])
    #expect(owned.map(\.weight) == [1, 2])
  }

  @Test func ownedCharactersDropWhatTheDatasetLacks() {
    let valid = OwnedCharacter.valid([
      OwnedCharacter(characterID: "furina", roleID: "kazuha.em-swirl-support"),
      OwnedCharacter(characterID: "nobody"),
      OwnedCharacter(characterID: "furina", building: true),
      OwnedCharacter(characterID: "raiden-shogun", roleID: "raiden-shogun.er-crit", building: true),
    ])
    #expect(valid.map(\.characterID) == ["furina", "raiden-shogun"])
    #expect(valid[0].roleID == Self.furina.roleID)
    #expect(valid[1].roleID == "raiden-shogun.er-crit" && valid[1].building)
  }

  @Test func bossOnlySetsAreListedApart() throws {
    let base = Self.furina
    // Four-star-only sets are passed over for the first five-star one.
    let gladiator = CharacterRole(
      characterID: base.characterID, characterName: base.characterName, roleID: "test.gladiator",
      roleName: base.roleName, mains: base.mains, usefulStats: base.usefulStats,
      secondaryStats: base.secondaryStats,
      sets: [
        RoleSet("Instructor", .preferred, ""), RoleSet("Gladiator's Finale", .alternative, ""),
      ],
      conditions: [], source: base.source)
    #expect(FarmingPlan.set(for: gladiator) == "Gladiator's Finale")
    let plan = Self.plan([gladiator])
    #expect(plan.domains.isEmpty)
    #expect(!plan.bossNeeds.isEmpty)
    #expect(plan.sets.first?.domain == nil && plan.sets.first?.hasDomain == false)
    #expect(!FarmingPlan.character(gladiator, inventory: []).hasDomain)
  }

  @Test func everyCharacterPlansInReasonableTime() {
    let start = Date()
    let plan = FarmingPlan.evaluate(roles: FarmingPlan.roles(owned: []), inventory: [])
    let seconds = Date().timeIntervalSince(start)
    print("Every character's plan took \(seconds) s")
    #expect(plan.domains.count > 10)
    #expect(seconds < 20)
  }
}
