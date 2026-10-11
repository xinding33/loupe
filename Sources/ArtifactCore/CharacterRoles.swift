import Foundation

public enum RoleConditionKind: String, Sendable {
  case energy, critBalance, team, rotation, setActivation, mainStat
}

public enum RoleConditionStatus: String, Sendable {
  case met, notMet, unknown
}

public struct RoleCondition: Sendable {
  public let kind: RoleConditionKind
  public let status: RoleConditionStatus
  public let explanation: String

  init(_ kind: RoleConditionKind, _ explanation: String) {
    self.kind = kind
    self.status = .unknown
    self.explanation = explanation
  }
}

public struct RoleSource: Sendable {
  public let url: String
  public let section: String
  public let sourceVersion: String
  public let reviewedOn: String
}

public enum CharacterSetFit: String, Sendable {
  case preferred, alternative, offPiece
}

public struct RoleSet: Sendable {
  public let name: String
  public let fit: CharacterSetFit
  public let requiredPieces: Int
  public let condition: String

  init(_ name: String, _ fit: CharacterSetFit, _ condition: String) {
    self.name = name
    self.fit = fit
    self.requiredPieces = 4
    self.condition = condition
  }
}

public struct CharacterRole: Sendable, Identifiable {
  public let characterID: String
  public let characterName: String
  public let roleID: String
  public let roleName: String
  public let mains: [Slot: [Stat]]
  public let usefulStats: [Stat]
  public let secondaryStats: [Stat]
  public let sets: [RoleSet]
  public let conditions: [RoleCondition]
  public let source: RoleSource
  public var id: String { roleID }
  public var profile: Profile {
    Profile(roleID, weights: Dictionary(uniqueKeysWithValues: usefulStats.map { ($0, 100) }))
  }
}

public enum CharacterRoles {
  public static let datasetVersion = "reviewed-2026-09-27.1"
  public static let coverageDescription =
    "15-character local review: Alhaitham, Bennett, Fischl, Furina, Itto, Kazuha, Kokomi, "
    + "Kuki Shinobu, Nahida, Neuvillette, Raiden Shogun, Sucrose, Xiangling, Xingqiu, and Yelan. "
    + "One reviewed role each; includes unowned characters and off-pieces. Not roster-wide. "
    + "Experimental grades cover 15 role/slot/main combinations for Furina, Itto, and Kuki. "
    + "Other combinations remain ungraded."
  public static let noMatchDescription =
    "No reviewed match in these 15 roles. Manual profiles remain available for other uses."
  public static let excludedCoverage =
    "No full-build optimization, ownership filter, constellation or weapon variants, "
    + "Itto plunge/DEF-goblet builds, Kuki Quicken/pure healing, or Kokomi off-field/Bloom roles. "
    + "Also excludes Neuvillette reaction-specific builds, Yelan/Xingqiu on-field or Bloom builds, "
    + "Fischl non-Aggravate/physical, Nahida on-field/Nilou Bloom, Alhaitham non-Spread, "
    + "Raiden Burst carry/Overloaded, Kazuha carry/Thundering Fury, Sucrose Lunar-Charged, "
    + "and Bennett damage/reaction-trigger variants. Mixed two-piece sets, four-star artifacts, "
    + "unreviewed equipment and all other characters are outside coverage."

  public static let reviewed: [CharacterRole] = (pilot + expanded).sorted {
    $0.characterID < $1.characterID
  }

  static let energy = RoleCondition(
    .energy,
    "ER requirement unknown: team, weapon, constellation, and rotation are not supplied. "
      + "ER not scored; depends on build. A card cannot establish Burst readiness.")
  static let crit = RoleCondition(
    .critBalance,
    "Effective Crit Rate and Crit balance are unknown. This fixed profile counts Crit rolls "
      + "without a cap; it cannot determine overcap waste or predict damage gains.")

  static func mains(_ sands: [Stat], _ goblet: [Stat], _ circlet: [Stat]) -> [Slot: [Stat]] {
    [.flower: [.hp], .plume: [.atk], .sands: sands, .goblet: goblet, .circlet: circlet]
  }

  private static func source(_ url: String, _ section: String, _ version: String) -> RoleSource {
    RoleSource(url: url, section: section, sourceVersion: version, reviewedOn: "2026-09-26")
  }

  public static let pilot: [CharacterRole] = [
    CharacterRole(
      characterID: "furina", characterName: "Furina", roleID: "furina.off-field-hp",
      roleName: "Off-field HP damage / Burst support",
      mains: mains(
        [.hpPercent, .energyRecharge], [.hpPercent, .hydroDamage], [.critRate, .critDamage]),
      usefulStats: [.hpPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge],
      sets: [
        RoleSet("Golden Troupe", .preferred, "Personal damage use assumes off-field Skill uptime."),
        RoleSet(
          "Tenacity of the Millelith", .alternative,
          "Team support use needs allies who benefit from ATK buffs."),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .team, "Assumes a team healer and off-field damage mode; team context is unknown."),
      ],
      source: source(
        "https://www.prydwen.gg/genshin-impact/characters/furina",
        "Build: artifacts, stats, energy", "2026-09-25")),
    CharacterRole(
      characterID: "itto", characterName: "Arataki Itto", roleID: "itto.on-field-def",
      roleName: "On-field DEF damage",
      mains: mains([.defPercent], [.geoDamage], [.critRate, .critDamage]),
      usefulStats: [.defPercent, .critRate, .critDamage],
      secondaryStats: [.energyRecharge, .atkPercent],
      sets: [
        RoleSet(
          "Husk of Opulent Dreams", .preferred, "Husk's value depends on maintaining its stacks.")
      ],
      conditions: [
        energy, crit,
        RoleCondition(.rotation, "Assumes on-field Burst damage, not a plunge-specific build."),
      ],
      source: source(
        "https://keqingmains.com/q/itto-quickguide/", "Artifacts: ER, stats, sets",
        "5.6; set calculations 3.1")),
    CharacterRole(
      characterID: "xiangling", characterName: "Xiangling", roleID: "xiangling.reverse-vaporize",
      roleName: "Reverse Vaporize Burst damage",
      mains: mains(
        [.energyRecharge, .elementalMastery, .atkPercent], [.pyroDamage], [.critRate, .critDamage]),
      usefulStats: [.atkPercent, .elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge],
      sets: [
        RoleSet(
          "Emblem of Severed Fate", .preferred,
          "Assumes Burst damage; required ER depends on the rotation."),
        RoleSet("Crimson Witch of Flames", .alternative, "Requires Pyro reaction damage."),
        RoleSet(
          "Gilded Dreams", .alternative,
          "Requires reaction damage and the appropriate team composition."),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .team,
          "Reverse Vaporize ownership is unknown. EM screening applies only when Xiangling triggers the reactions."
        ),
      ],
      source: source(
        "https://keqingmains.com/q/xiangling-quickguide/", "Artifacts: ER, stats, sets", "4.5")),
    CharacterRole(
      characterID: "kuki-shinobu", characterName: "Kuki Shinobu", roleID: "kuki-shinobu.hyperbloom",
      roleName: "Hyperbloom trigger",
      mains: mains([.elementalMastery], [.elementalMastery], [.elementalMastery]),
      usefulStats: [.elementalMastery], secondaryStats: [.energyRecharge, .hpPercent],
      sets: [
        RoleSet("Flower of Paradise Lost", .preferred, "Requires Shinobu to trigger Hyperbloom."),
        RoleSet(
          "Gilded Dreams", .alternative,
          "Requires reactions; the EM bonus depends on team elements."),
      ],
      conditions: [
        RoleCondition(
          .team,
          "Hyperbloom ownership and character level are unknown; assumes Shinobu triggers Dendro cores."
        ),
        RoleCondition(
          .energy,
          "ER supports optional Burst use; do not trade EM for a Burst target. HP% is healing utility."
        ),
      ],
      source: source(
        "https://keqingmains.com/q/shinobu-quickguide/", "Hyperbloom: ER, stats, sets", "5.4")),
    CharacterRole(
      characterID: "kokomi", characterName: "Sangonomiya Kokomi", roleID: "kokomi.on-field-healer",
      roleName: "On-field healer / enabler",
      mains: mains([.hpPercent, .energyRecharge], [.hydroDamage, .hpPercent], [.healing]),
      usefulStats: [.hpPercent], secondaryStats: [.energyRecharge, .hp],
      sets: [
        RoleSet(
          "Ocean-Hued Clam", .preferred,
          "Assumes on-field Burst healing; one piece does not establish Clam damage."),
        RoleSet(
          "Tenacity of the Millelith", .alternative,
          "Team support use needs allies who benefit from ATK buffs."),
      ],
      conditions: [
        energy,
        RoleCondition(
          .rotation,
          "Assumes on-field Burst use. Standard Kokomi has a Crit Rate penalty; neither Crit stat counts in this profile."
        ),
      ],
      source: source(
        "https://keqingmains.com/q/kokomi-quickguide/",
        "On-field healer/enabler; Flawless Strategy", "Luna V")),
  ]
}
