import Foundation
import LoupeCore
import Testing

// Genshin Optimizer's English set names at commit 7d1fcb7 (MIT), to catch misspelled sets.
private let knownSets: Set<String> = [
  "A Day Carved From Rising Winds", "Adventurer", "Archaic Petra",
  "Aubade of Morningstar and Moon", "Berserker", "Blizzard Strayer", "Bloodstained Chivalry",
  "Brave Heart", "Celestial Gift", "Crimson Witch of Flames", "Deepwood Memories",
  "Defender's Will", "Desert Pavilion Chronicle", "Disenchantment in Deep Shadow",
  "Echoes of an Offering", "Emblem of Severed Fate", "Finale of the Deep Galleries",
  "Flower of Paradise Lost", "Fragment of Harmonic Whimsy", "Gambler", "Gilded Dreams",
  "Gladiator's Finale", "Golden Troupe", "Heart of Depth", "Heart of the Furnace",
  "Husk of Opulent Dreams", "Instructor", "Lavawalker", "Long Night's Oath", "Lucky Dog",
  "Maiden Beloved", "Marechaussee Hunter", "Martial Artist", "Night of the Sky's Unveiling",
  "Nighttime Whispers in the Echoing Woods", "Noblesse Oblige", "Nymph's Dream",
  "Obsidian Codex", "Ocean-Hued Clam", "Pale Flame", "Prayers for Destiny",
  "Prayers for Illumination", "Prayers for Wisdom", "Prayers to Springtime",
  "Resolution of Sojourner", "Retracing Bolide", "Scarlet Proof", "Scholar",
  "Scroll of the Hero of Cinder City", "Shimenawa's Reminiscence", "Silken Moon's Serenade",
  "Song of Days Past", "Tenacity of the Millelith", "The Exile", "Thundering Fury",
  "Thundersoother", "Tiny Miracle", "Traveling Doctor", "Unfinished Reverie",
  "Vermillion Hereafter", "Viridescent Venerer", "Vourukasha's Glow", "Wanderer's Troupe",
]

private func flower(_ substats: [Substat], set: String = "Test off-piece") throws -> Artifact {
  try Artifact(setName: set, slot: .flower, main: .hp, level: 20, substats: substats)
}

@Test func archetypesHaveDistinctScoredStatsAndAreAllUsed() {
  #expect(Set(Archetype.all.map { Set($0.usefulStats) }).count == Archetype.all.count)
  #expect(Set(Archetype.all.map(\.id)) == Set(ArchetypeID.allCases))
  let used = Set(Roster.characters.flatMap(\.archetypes))
  #expect(used == Set(ArchetypeID.allCases))
}

@Test func rosterIdentitiesAndSetsAreValid() {
  let ids = Roster.characters.map(\.id)
  #expect(Set(ids).count == ids.count)
  #expect(Set(Roster.characters.map(\.name)).count == ids.count)
  #expect(Roster.characters.count >= 120)
  for character in Roster.characters {
    #expect(!character.archetypes.isEmpty, "\(character.name)")
    #expect(!character.sets.isEmpty, "\(character.name)")
    for set in character.sets { #expect(knownSets.contains(set), "\(character.name): \(set)") }
  }
  let roleIDs = CharacterRoles.all.map(\.roleID)
  #expect(Set(roleIDs).count == roleIDs.count)
}

@Test func everyReviewedRoleKeepsItsPlaceInTheRoster() throws {
  for role in CharacterRoles.reviewed {
    let archetype = try #require(role.archetype, "\(role.roleID)")
    let character = try #require(Roster.characters.first { $0.id == role.characterID })
    #expect(character.archetypes.contains(archetype), "\(role.roleID)")
    #expect(character.name == role.characterName)
    let same = CharacterRoles.all.filter {
      $0.characterID == role.characterID && $0.archetype == archetype
    }
    #expect(same.map(\.roleID) == [role.roleID])
    #expect(same.first?.isReviewed == true)
  }
}

@Test func archetypeRolesUseTheCharactersGobletAndSayTheyAreUnreviewed() throws {
  func roles(_ id: String) -> [CharacterRole] { CharacterRoles.all.filter { $0.characterID == id } }
  let sandrone = try #require(roles("sandrone").first)
  #expect(sandrone.mains[.goblet] == [.atkPercent])
  #expect(sandrone.usefulStats.contains(.elementalMastery))
  #expect(try #require(roles("eula").first).mains[.goblet] == [.physicalDamage])
  #expect(try #require(roles("furina").first).mains[.goblet]?.contains(.hydroDamage) == true)
  let raiden = roles("raiden-shogun")
  #expect(raiden.map(\.roleID) == ["raiden-shogun.hyperbloom", "raiden-shogun.er-crit"])
  let burst = raiden[1]
  #expect(!burst.isReviewed)
  #expect(burst.usefulStats.contains(.energyRecharge))
  #expect(burst.conditions.contains { $0.kind == .coverage })
  #expect(burst.sets.first?.name == "Emblem of Severed Fate")
  #expect(burst.sets.first?.fit == .preferred)
}

@Test func archetypeRolesDoNotChangeReviewedAdvice() throws {
  let pieces = [
    try flower([
      Substat(.elementalMastery, 139.86), Substat(.atk, 19.45), Substat(.def, 23.15),
      Substat(.hpPercent, 5.83),
    ]),
    try flower(
      [
        Substat(.critRate, 10.89), Substat(.critDamage, 21.76), Substat(.hpPercent, 9.91),
        Substat(.atk, 19.45),
      ], set: "Golden Troupe"),
    try Artifact(
      setName: "Emblem of Severed Fate", slot: .sands, main: .energyRecharge, level: 0,
      substats: [Substat(.critRate, 3.89), Substat(.atkPercent, 5.83), Substat(.hp, 298.75)],
      unactivated: Substat(.critDamage, 7.77)),
  ]
  for piece in pieces {
    let reviewed = CharacterAssessment.evaluate(piece, roles: CharacterRoles.reviewed)
    let all = CharacterAssessment.evaluate(piece)
    for match in reviewed {
      let same = try #require(all.first { $0.roleID == match.roleID })
      #expect(same.setFit == match.setFit)
      #expect(same.potential?.currentScore == match.potential?.currentScore)
      #expect(same.potential?.expectedScore == match.potential?.expectedScore)
      #expect(same.grades?.current == match.grades?.current)
      #expect(same.grades?.p50 == match.grades?.p50)
      #expect(same.conditions.map(\.explanation) == match.conditions.map(\.explanation))
    }
  }
}

@Test func charactersSharingAnArchetypeShareTheForecast() throws {
  let piece = try Artifact(
    setName: "Test off-piece", slot: .goblet, main: .cryoDamage, level: 4,
    substats: [
      Substat(.critRate, 6.61), Substat(.atkPercent, 5.83), Substat(.energyRecharge, 6.48),
      Substat(.critDamage, 7.77),
    ])
  let matches = CharacterAssessment.evaluate(piece).filter { $0.role.archetype == .atkCrit }
  #expect(matches.count > 3)
  let first = try #require(matches.first?.potential)
  for match in matches {
    #expect(match.potential?.expectedScore == first.expectedScore)
    #expect(match.grades?.p50 == matches[0].grades?.p50)
  }
}

@Test func healingCircletsFitOnlySupportsWhoHeal() throws {
  let circlet = try Artifact(
    setName: "Noblesse Oblige", slot: .circlet, main: .healing, level: 20,
    substats: [
      Substat(.atkPercent, 29.15), Substat(.energyRecharge, 12.96), Substat(.def, 23.15),
      Substat(.hp, 298.75),
    ])
  let users = Set(CharacterAssessment.evaluate(circlet).map(\.characterID))
  #expect(!users.contains("shenhe"))
  #expect(!users.contains("yun-jin"))
  #expect(users.contains("jean"))
  #expect(users.contains("iansan"))
  #expect(users.contains("kokomi"))
  let shenhe = try #require(CharacterRoles.all.first { $0.characterID == "shenhe" })
  #expect(shenhe.mains[.circlet] == [.atkPercent, .critRate])
}

@Test func dendroTravelerTakesAnEnergySands() throws {
  let sands = try Artifact(
    setName: "Deepwood Memories", slot: .sands, main: .energyRecharge, level: 0,
    substats: [
      Substat(.elementalMastery, 23.31), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
    ])
  #expect(CharacterAssessment.evaluate(sands).contains { $0.characterID == "traveler-dendro" })
}
