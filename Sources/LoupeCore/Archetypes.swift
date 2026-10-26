import Foundation

/// A stat profile shared by many characters. Grading depends only on the scored stats and the
/// eligible mains, so characters with the same archetype get the same grade for a piece.
public enum ArchetypeID: String, CaseIterable, Sendable {
  case atkCrit = "atk-crit"
  case atkEMCrit = "atk-em-crit"
  case hpCrit = "hp-crit"
  case hpEMCrit = "hp-em-crit"
  case defCrit = "def-crit"
  case emCrit = "em-crit"
  case erCrit = "er-crit"
  case em
  case hpSupport = "hp-support"
  case atkSupport = "atk-support"
  case defSupport = "def-support"
  case erSupport = "er-support"
}

public struct Archetype: Sendable, Identifiable {
  public let id: ArchetypeID
  public let name: String
  public let summary: String
  public let usefulStats: [Stat]
  public let secondaryStats: [Stat]
  let sands: [Stat]
  /// Goblet mains besides the character's own DMG Bonus, which `damageGoblet` adds.
  let goblet: [Stat]
  let damageGoblet: Bool
  let circlet: [Stat]
  let conditions: [RoleCondition]

  /// Healing Bonus circlets fit a support archetype only for characters who heal.
  func mains(damage: Stat, heals: Bool) -> [Slot: [Stat]] {
    let healer = heals && [.hpSupport, .atkSupport, .defSupport].contains(id)
    return CharacterRoles.mains(
      sands, (damageGoblet ? [damage] : []) + goblet, circlet + (healer ? [.healing] : []))
  }

  public static let all: [Archetype] = [
    Archetype(
      id: .atkCrit, name: "ATK crit damage",
      summary: "Damage dealers that scale on ATK and do not rely on Elemental Mastery.",
      usefulStats: [.atkPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge],
      sands: [.atkPercent, .energyRecharge], goblet: [], damageGoblet: true,
      circlet: [.critRate, .critDamage], conditions: [energy, crit]),
    Archetype(
      id: .atkEMCrit, name: "ATK reaction damage",
      summary: "ATK damage dealers that trigger Vaporize, Melt, Aggravate or similar reactions.",
      usefulStats: [.atkPercent, .elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge],
      sands: [.atkPercent, .elementalMastery, .energyRecharge], goblet: [], damageGoblet: true,
      circlet: [.critRate, .critDamage],
      conditions: [energy, crit, reaction]),
    Archetype(
      id: .hpCrit, name: "HP crit damage",
      summary: "Damage dealers whose talents scale on Max HP.",
      usefulStats: [.hpPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge],
      sands: [.hpPercent, .energyRecharge], goblet: [.hpPercent], damageGoblet: true,
      circlet: [.critRate, .critDamage], conditions: [energy, crit]),
    Archetype(
      id: .hpEMCrit, name: "HP reaction damage",
      summary: "HP-scaling damage dealers that trigger Vaporize or Melt themselves.",
      usefulStats: [.hpPercent, .elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge],
      sands: [.hpPercent, .elementalMastery], goblet: [], damageGoblet: true,
      circlet: [.critRate, .critDamage], conditions: [energy, crit, reaction]),
    Archetype(
      id: .defCrit, name: "DEF crit damage",
      summary: "Damage dealers whose talents scale on DEF.",
      usefulStats: [.defPercent, .critRate, .critDamage],
      secondaryStats: [.energyRecharge, .atkPercent],
      sands: [.defPercent, .energyRecharge], goblet: [], damageGoblet: true,
      circlet: [.critRate, .critDamage], conditions: [energy, crit]),
    Archetype(
      id: .emCrit, name: "EM crit damage",
      summary: "Damage dealers whose talents scale on Elemental Mastery and can crit.",
      usefulStats: [.elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge, .atkPercent],
      sands: [.elementalMastery, .atkPercent], goblet: [.elementalMastery], damageGoblet: true,
      circlet: [.critRate, .critDamage, .elementalMastery], conditions: [energy, crit]),
    Archetype(
      id: .erCrit, name: "Energy-scaling Burst damage",
      summary: "Damage dealers whose own passive turns Energy Recharge into damage.",
      usefulStats: [.energyRecharge, .atkPercent, .critRate, .critDamage], secondaryStats: [],
      sands: [.energyRecharge, .atkPercent], goblet: [.atkPercent], damageGoblet: true,
      circlet: [.critRate, .critDamage], conditions: [crit]),
    Archetype(
      id: .em, name: "EM reaction support",
      summary: "Characters valued for Swirl, Bloom-family or other transformative reactions.",
      usefulStats: [.elementalMastery], secondaryStats: [.energyRecharge],
      sands: [.elementalMastery, .energyRecharge], goblet: [.elementalMastery], damageGoblet: false,
      circlet: [.elementalMastery], conditions: [energy, transformative]),
    Archetype(
      id: .hpSupport, name: "HP healer / shield / buffer",
      summary: "Supports whose healing, shields or buffs scale on Max HP.",
      usefulStats: [.hpPercent], secondaryStats: [.energyRecharge, .hp],
      sands: [.hpPercent, .energyRecharge], goblet: [.hpPercent], damageGoblet: false,
      circlet: [.hpPercent, .critRate], conditions: [energy, support]),
    Archetype(
      id: .atkSupport, name: "ATK healer / buffer",
      summary: "Supports whose healing or buffs scale on ATK and need Energy for their Burst.",
      usefulStats: [.atkPercent, .energyRecharge], secondaryStats: [.atk, .critRate],
      sands: [.atkPercent, .energyRecharge], goblet: [.atkPercent], damageGoblet: false,
      circlet: [.atkPercent, .critRate], conditions: [energy, support]),
    Archetype(
      id: .defSupport, name: "DEF shield / buffer",
      summary: "Supports whose shields, healing or buffs scale on DEF and need Energy.",
      usefulStats: [.defPercent, .energyRecharge], secondaryStats: [.def, .critRate],
      sands: [.defPercent, .energyRecharge], goblet: [.defPercent], damageGoblet: false,
      circlet: [.defPercent, .critRate], conditions: [energy, support]),
    Archetype(
      id: .erSupport, name: "Energy / Burst support",
      summary:
        "Supports that need enough Energy Recharge to keep a Burst buff up, usually with a "
        + "Favonius weapon that rewards CRIT Rate.",
      usefulStats: [.energyRecharge, .critRate], secondaryStats: [.atkPercent, .hpPercent],
      sands: [.energyRecharge], goblet: [.atkPercent, .hpPercent], damageGoblet: true,
      circlet: [.critRate, .atkPercent, .hpPercent], conditions: [support]),
  ]

  public static func named(_ id: ArchetypeID) -> Archetype { all.first { $0.id == id }! }

  static let energy = CharacterRoles.energy
  static let crit = CharacterRoles.crit
  static let reaction = RoleCondition(
    .team, "EM counts only when this character triggers the reactions; the team is unknown.")
  static let transformative = RoleCondition(
    .team,
    "Crit and ATK do not raise Swirl, Bloom-family or other transformative reaction damage.")
  static let support = RoleCondition(
    .team,
    "Support value depends on who benefits from the buff, heal or shield; the team is unknown.")
}

/// One character's archetype assignment: the facts that change advice, not a full build.
public struct RosterCharacter: Sendable {
  public let id: String
  public let name: String
  /// The goblet main this character uses for the archetype's DMG Bonus slot: its element,
  /// Physical, or ATK% for carries of Snezhnaya's Stellar reactions.
  public let damage: Stat
  public let archetypes: [ArchetypeID]
  /// Four-piece sets, preferred first.
  public let sets: [String]
  /// Whether the character heals, which makes Healing Bonus circlets fit its support roles.
  public let heals: Bool

  init(
    _ id: String, _ name: String, _ damage: Stat, _ archetypes: [ArchetypeID], _ sets: [String],
    heals: Bool = false
  ) {
    self.id = id
    self.name = name
    self.damage = damage
    self.archetypes = archetypes
    self.sets = sets
    self.heals = heals
  }

  func role(_ archetype: Archetype) -> CharacterRole {
    CharacterRole(
      characterID: id, characterName: name, roleID: "\(id).\(archetype.id.rawValue)",
      roleName: "\(archetype.name) (archetype)",
      mains: archetype.mains(damage: damage, heals: heals),
      usefulStats: archetype.usefulStats, secondaryStats: archetype.secondaryStats,
      sets: sets.enumerated().map { index, set in
        RoleSet(
          set, index == 0 ? .preferred : .alternative,
          "Set choice comes from the archetype table and was not reviewed for this character.")
      },
      conditions: archetype.conditions + [
        RoleCondition(
          .coverage,
          "Archetype role, not individually reviewed: core stats come from \"\(archetype.name)\". "
            + "This character's own ER needs, weapon and team are not modeled.")
      ],
      source: RoleSource(
        url: "https://github.com/xinding33/loupe/blob/main/docs/archetypes.md",
        section: "Archetypes: \(archetype.name)", sourceVersion: Roster.version,
        reviewedOn: Roster.assignedOn),
      isReviewed: false)
  }
}
