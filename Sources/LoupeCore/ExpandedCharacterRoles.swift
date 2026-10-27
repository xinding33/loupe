extension CharacterRoles {
  private static func expansionSource(
    _ character: String, _ section: String, _ version: String
  ) -> RoleSource {
    RoleSource(
      url: "https://keqingmains.com/q/\(character)-quickguide/", section: section,
      sourceVersion: version, reviewedOn: "2026-09-27")
  }

  private static let favonius = RoleCondition(
    .rotation,
    "Favonius Crit Rate utility requires that weapon and on-field hits. Weapon and proc reliability "
      + "are unknown; no proc odds or extra Crit weight are assigned.")

  static let expanded: [CharacterRole] = [
    CharacterRole(
      characterID: "alhaitham", characterName: "Alhaitham", roleID: "alhaitham.spread",
      roleName: "On-field Spread damage",
      mains: mains([.elementalMastery, .atkPercent], [.dendroDamage], [.critRate, .critDamage]),
      usefulStats: [.elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge, .atkPercent],
      sets: [
        RoleSet(
          "Gilded Dreams", .preferred,
          "Requires reactions and a teammate supplying Deepwood's Dendro resistance reduction."),
        RoleSet(
          "Deepwood Memories", .alternative,
          "Use when no teammate supplies its resistance reduction; requires Skill or Burst hits."),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .team,
          "Assumes Quicken uptime and Alhaitham triggering Spread. EM buffs, weapon scaling and mirror uptime are unknown. ATK% remains secondary."
        ),
        RoleCondition(
          .mainStat,
          "ATK% sands are a fallback to EM for this Spread role, not an equal damage recommendation."
        ),
      ],
      source: expansionSource("alhaitham", "Artifacts; Quicken; mirror mechanics", "4.7")),
    CharacterRole(
      characterID: "bennett", characterName: "Bennett", roleID: "bennett.healing-support",
      roleName: "Healing / ATK support",
      mains: mains([.energyRecharge, .hpPercent], [.hpPercent], [.healing, .hpPercent]),
      usefulStats: [.hpPercent], secondaryStats: [.energyRecharge, .hp, .critRate],
      sets: [
        RoleSet(
          "Noblesse Oblige", .preferred,
          "Requires Burst use and allies who benefit from ATK; duplicate set buffs do not stack."),
        RoleSet(
          "Scroll of the Hero of Cinder City", .alternative,
          "Requires Bennett to trigger a relevant reaction; no Nightsoul-enhanced bonus assumed."),
        RoleSet(
          "Instructor", .alternative,
          "Four-star. For teams whose damage comes from EM reactions, or when another character "
            + "holds Noblesse Oblige; Bennett must trigger a reaction."),
        RoleSet(
          "The Exile", .alternative,
          "Four-star Energy option for newer accounts; Noblesse Oblige or Instructor serve the "
            + "team better."),
      ],
      conditions: [
        energy, favonius,
        RoleCondition(
          .team,
          "Burst buff uses base ATK from character and weapon. Artifact ATK% and flat ATK do not improve it. HP% screens healing only; healing needs and buff uptime are unknown."
        ),
      ],
      source: expansionSource("bennett", "Artifacts: Healing Support; sets; weapons", "5.7")),
    CharacterRole(
      characterID: "fischl", characterName: "Fischl", roleID: "fischl.off-field-aggravate",
      roleName: "Off-field Aggravate damage",
      mains: mains([.atkPercent, .elementalMastery], [.electroDamage], [.critRate, .critDamage]),
      usefulStats: [.atkPercent, .elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge],
      sets: [
        RoleSet("Golden Troupe", .preferred, "Requires off-field Oz damage and Skill uptime."),
        RoleSet(
          "Gilded Dreams", .alternative,
          "Requires reactions and team-dependent buffs; summon Oz after activating the set."),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .team,
          "EM screening assumes Fischl triggers Aggravate with Quicken uptime. Non-Aggravate teams and physical on-field builds are excluded."
        ),
        RoleCondition(.rotation, "Oz uptime depends on Skill/Burst scheduling and constellation."),
      ],
      source: expansionSource("fischl", "Off-field DPS; Artifacts; Quicken", "4.0")),
    CharacterRole(
      characterID: "kazuha", characterName: "Kaedehara Kazuha", roleID: "kazuha.em-swirl-support",
      roleName: "EM Swirl support",
      mains: mains([.elementalMastery, .energyRecharge], [.elementalMastery], [.elementalMastery]),
      usefulStats: [.elementalMastery], secondaryStats: [.energyRecharge, .critRate],
      sets: [
        RoleSet(
          "Viridescent Venerer", .preferred,
          "Requires on-field Swirl of the element to be reduced; Dendro cannot be Swirled.")
      ],
      conditions: [
        energy, favonius,
        RoleCondition(
          .team,
          "Assumes Swirl and an ally who benefits from the Swirled element's damage buff. Character level, aura and rotation are unknown. Crit does not increase Swirl damage."
        ),
      ],
      source: expansionSource("kazuha", "Builds: ER, stats, sets; support playstyle", "4.6")),
    CharacterRole(
      characterID: "nahida", characterName: "Nahida", roleID: "nahida.off-field-dendro",
      roleName: "Off-field Dendro reaction support",
      mains: mains(
        [.elementalMastery], [.elementalMastery, .dendroDamage],
        [.elementalMastery, .critRate, .critDamage]),
      usefulStats: [.elementalMastery, .critRate, .critDamage],
      secondaryStats: [.energyRecharge, .atkPercent],
      sets: [
        RoleSet(
          "Deepwood Memories", .preferred,
          "Requires Skill or Burst hits; only one teammate needs to supply its resistance reduction."
        ),
        RoleSet(
          "Gilded Dreams", .alternative,
          "Requires reactions and suitable team elements; another holder must cover needed Deepwood uptime."
        ),
        RoleSet(
          "Instructor", .alternative,
          "Four-star. For teams where others deal the damage; Nahida must trigger a reaction."),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .team,
          "EM and Crit screen off-field Skill damage, including Spread when available. Nahida is not assumed to own Hyperbloom. EM-share source, passive caps and team buffs are unknown; no cap-aware buff or damage score."
        ),
        RoleCondition(
          .rotation,
          "Assumes off-field Skill application. Burst value depends on the team; on-field and Nilou Bloom variants are excluded."
        ),
      ],
      source: expansionSource(
        "nahida", "Off-Field; Artifacts; A1/A4 passives", "5.6; set calculations 3.8")),
    CharacterRole(
      characterID: "neuvillette", characterName: "Neuvillette", roleID: "neuvillette.on-field-hp",
      roleName: "On-field HP Charged Attack damage",
      mains: mains(
        [.hpPercent], [.hydroDamage, .hpPercent], [.critRate, .critDamage, .hpPercent]),
      usefulStats: [.hpPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge, .hp],
      sets: [
        RoleSet(
          "Marechaussee Hunter", .preferred,
          "Requires HP changes for Crit Rate stacks; full-build Crit overcap is not checked."),
        RoleSet(
          "Heart of Depth", .alternative,
          "Requires Skill use to buff the subsequent Charged Attacks; a placeholder for Marechaussee."
        ),
      ],
      conditions: [
        energy, crit,
        RoleCondition(
          .rotation,
          "Assumes enhanced Charged Attacks and enough droplets from Skill/Burst. Reaction-specific EM builds are excluded."
        ),
        RoleCondition(
          .mainStat,
          "HP% goblet or circlet can be alternatives depending on weapon and buffs. Independent eligibility does not recommend triple HP% or compare mains."
        ),
      ],
      source: expansionSource(
        "neuvillette", "On-Field DPS; Artifacts", "Luna IV; set calculations 5.8")),
    CharacterRole(
      characterID: "raiden-shogun", characterName: "Raiden Shogun",
      roleID: "raiden-shogun.hyperbloom",
      roleName: "Off-field Hyperbloom trigger",
      mains: mains([.elementalMastery], [.elementalMastery], [.elementalMastery]),
      usefulStats: [.elementalMastery], secondaryStats: [],
      sets: [
        RoleSet("Flower of Paradise Lost", .preferred, "Requires Raiden to trigger Hyperbloom."),
        RoleSet(
          "Gilded Dreams", .alternative,
          "Requires reactions; the EM bonus depends on the team's elements."),
        RoleSet(
          "Deepwood Memories", .alternative,
          "Only when no teammate can supply its resistance reduction; needs Skill hits."),
      ],
      conditions: [
        RoleCondition(
          .team,
          "Assumes Raiden's Skill triggers Dendro cores. Reaction ownership and character level are unknown; Crit and ATK do not increase Hyperbloom damage."
        ),
        RoleCondition(
          .energy,
          "This Skill-only role does not need Burst ER. Burst carry and hybrid damage builds are excluded; ER receives no score."
        ),
      ],
      source: expansionSource("raiden", "Hyperbloom / Overloaded Trigger: Hyperbloom subset", "5.7")
    ),
    CharacterRole(
      characterID: "sucrose", characterName: "Sucrose", roleID: "sucrose.em-reaction-support",
      roleName: "EM reaction support",
      mains: mains([.elementalMastery], [.elementalMastery], [.elementalMastery]),
      usefulStats: [.elementalMastery], secondaryStats: [.energyRecharge, .critRate],
      sets: [
        RoleSet(
          "Viridescent Venerer", .preferred,
          "Requires on-field Swirl of a relevant element; Dendro cannot be Swirled."),
        RoleSet(
          "Deepwood Memories", .alternative,
          "Dendro-team support only, when another holder does not cover the needed resistance reduction."
        ),
      ],
      conditions: [
        favonius,
        RoleCondition(
          .energy,
          "Burst is optional in this role. ER helps when the rotation uses it; no required ER total is inferred."
        ),
        RoleCondition(
          .team,
          "Assumes allies benefit from EM sharing or Sucrose triggers transformative reactions. Level, aura and ownership are unknown. Lunar-Charged Crit effects are excluded."
        ),
      ],
      source: expansionSource("sucrose", "Artifacts: ER, stats, sets; EM support", "Luna VI")),
    CharacterRole(
      characterID: "xingqiu", characterName: "Xingqiu", roleID: "xingqiu.off-field-burst",
      roleName: "Off-field ATK Burst damage",
      mains: mains([.energyRecharge, .atkPercent], [.hydroDamage], [.critRate, .critDamage]),
      usefulStats: [.atkPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge],
      sets: [
        RoleSet(
          "Emblem of Severed Fate", .preferred, "Requires Burst uptime; ER is not a damage weight."),
        RoleSet(
          "Noblesse Oblige", .alternative,
          "Team-support tradeoff when allies benefit from ATK; duplicate set buffs do not stack."),
      ],
      conditions: [
        energy, crit, favonius,
        RoleCondition(
          .rotation,
          "Assumes off-field rain-sword damage driven by Normal Attacks. Constellation, weapon procs and particle routing change ER needs. Reaction ownership is not assumed."
        ),
      ],
      source: expansionSource("xingqiu", "Off-Field DPS; Artifacts; weapons", "5.7")),
    CharacterRole(
      characterID: "yelan", characterName: "Yelan", roleID: "yelan.off-field-hp",
      roleName: "Off-field HP Burst damage",
      mains: mains(
        [.hpPercent, .energyRecharge], [.hydroDamage, .hpPercent],
        [.critRate, .critDamage, .hpPercent]),
      usefulStats: [.hpPercent, .critRate, .critDamage], secondaryStats: [.energyRecharge],
      sets: [
        RoleSet(
          "Emblem of Severed Fate", .preferred,
          "Requires Burst uptime; extra ER is not automatically better."),
        RoleSet(
          "Nymph's Dream", .alternative,
          "Low-ER fallback only; stack activation and uptime depend on the rotation."),
      ],
      conditions: [
        energy, crit, favonius,
        RoleCondition(
          .rotation,
          "Assumes off-field Burst damage with Normal Attack triggers. ATK is not core; C6/on-field and reaction-trigger builds are excluded."
        ),
        RoleCondition(
          .mainStat,
          "HP% goblet or circlet is an alternative when build HP is low, not both together. HP totals and buffs are unknown; no target or main-stat comparison is scored."
        ),
      ],
      source: expansionSource("yelan", "Off-Field DPS & Enabler; Artifacts; weapons", "5.4")),
  ]
}
