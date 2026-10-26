/// Every playable character's archetypes, goblet and four-piece sets, as listed in
/// docs/archetypes.md. Reviewed characters keep their reviewed role for the archetype it matches.
public enum Roster {
  public static let version = "archetypes-2026-10-26.1"
  static let assignedOn = "2026-10-26"

  public static let characters: [RosterCharacter] = [
    // Reviewed characters: their reviewed role covers the first archetype.
    RosterCharacter(
      "alhaitham", "Alhaitham", .dendroDamage, [.emCrit], ["Gilded Dreams", "Deepwood Memories"]),
    RosterCharacter(
      "bennett", "Bennett", .pyroDamage, [.hpSupport],
      ["Noblesse Oblige", "Scroll of the Hero of Cinder City", "Instructor", "The Exile"]),
    RosterCharacter(
      "fischl", "Fischl", .electroDamage, [.atkEMCrit], ["Golden Troupe", "Gilded Dreams"]),
    RosterCharacter(
      "furina", "Furina", .hydroDamage, [.hpCrit], ["Golden Troupe", "Tenacity of the Millelith"]),
    RosterCharacter("itto", "Arataki Itto", .geoDamage, [.defCrit], ["Husk of Opulent Dreams"]),
    RosterCharacter("kazuha", "Kaedehara Kazuha", .anemoDamage, [.em], ["Viridescent Venerer"]),
    RosterCharacter(
      "kokomi", "Sangonomiya Kokomi", .hydroDamage, [.hpSupport],
      ["Ocean-Hued Clam", "Tenacity of the Millelith"]),
    RosterCharacter(
      "kuki-shinobu", "Kuki Shinobu", .electroDamage, [.em],
      ["Flower of Paradise Lost", "Gilded Dreams", "Instructor"]),
    RosterCharacter(
      "nahida", "Nahida", .dendroDamage, [.emCrit],
      ["Deepwood Memories", "Gilded Dreams", "Instructor"]),
    RosterCharacter(
      "neuvillette", "Neuvillette", .hydroDamage, [.hpCrit],
      ["Marechaussee Hunter", "Heart of Depth"]),
    RosterCharacter(
      "raiden-shogun", "Raiden Shogun", .electroDamage, [.em, .erCrit], ["Emblem of Severed Fate"]),
    RosterCharacter(
      "sucrose", "Sucrose", .anemoDamage, [.em], ["Viridescent Venerer", "Deepwood Memories"]),
    RosterCharacter(
      "xiangling", "Xiangling", .pyroDamage, [.atkEMCrit],
      ["Emblem of Severed Fate", "Crimson Witch of Flames"]),
    RosterCharacter(
      "xingqiu", "Xingqiu", .hydroDamage, [.atkCrit], ["Emblem of Severed Fate", "Noblesse Oblige"]),
    RosterCharacter(
      "yelan", "Yelan", .hydroDamage, [.hpCrit], ["Emblem of Severed Fate", "Nymph's Dream"]),

    // Anemo
    RosterCharacter(
      "chasca", "Chasca", .atkPercent, [.atkCrit], ["Obsidian Codex", "Marechaussee Hunter"]),
    RosterCharacter(
      "ifa", "Ifa", .anemoDamage, [.em, .atkCrit], ["Viridescent Venerer", "Obsidian Codex"]),
    RosterCharacter(
      "jahoda", "Jahoda", .anemoDamage, [.atkSupport],
      ["Viridescent Venerer", "Silken Moon's Serenade"], heals: true),
    RosterCharacter(
      "lan-yan", "Lan Yan", .anemoDamage, [.atkSupport, .em],
      ["Viridescent Venerer", "Scroll of the Hero of Cinder City"]),
    RosterCharacter(
      "varka", "Varka", .atkPercent, [.atkCrit],
      ["A Day Carved From Rising Winds", "Shimenawa's Reminiscence"]),
    RosterCharacter(
      "yumemizuki-mizuki", "Yumemizuki Mizuki", .anemoDamage, [.em],
      ["Viridescent Venerer", "Gilded Dreams"]),
    RosterCharacter(
      "traveler-anemo", "Traveler (Anemo)", .anemoDamage, [.em], ["Viridescent Venerer"]),
    RosterCharacter(
      "faruzan", "Faruzan", .anemoDamage, [.erSupport],
      ["Tenacity of the Millelith", "Noblesse Oblige", "The Exile"]),
    RosterCharacter(
      "jean", "Jean", .anemoDamage, [.atkSupport], ["Viridescent Venerer", "Ocean-Hued Clam"],
      heals: true),
    RosterCharacter("lynette", "Lynette", .anemoDamage, [.atkCrit], ["Viridescent Venerer"]),
    RosterCharacter(
      "prune", "Prune", .anemoDamage, [.atkSupport], ["Viridescent Venerer", "Celestial Gift"]),
    RosterCharacter("sayu", "Sayu", .anemoDamage, [.em], ["Viridescent Venerer"]),
    RosterCharacter(
      "shikanoin-heizou", "Shikanoin Heizou", .anemoDamage, [.atkCrit, .em], ["Viridescent Venerer"]
    ),
    RosterCharacter("venti", "Venti", .anemoDamage, [.em, .atkCrit], ["Viridescent Venerer"]),
    RosterCharacter(
      "vesna", "Vesna", .atkPercent, [.atkCrit], ["Scarlet Proof", "Viridescent Venerer"]),
    RosterCharacter(
      "wanderer", "Wanderer", .anemoDamage, [.atkCrit],
      ["Desert Pavilion Chronicle", "Shimenawa's Reminiscence"]),
    RosterCharacter(
      "xianyun", "Xianyun", .anemoDamage, [.atkSupport],
      ["Song of Days Past", "Viridescent Venerer"], heals: true),
    RosterCharacter(
      "xiao", "Xiao", .anemoDamage, [.atkCrit],
      ["Vermillion Hereafter", "Desert Pavilion Chronicle"]),

    // Cryo
    RosterCharacter(
      "citlali", "Citlali", .cryoDamage, [.em],
      ["Scroll of the Hero of Cinder City", "Tenacity of the Millelith"]),
    RosterCharacter(
      "escoffier", "Escoffier", .cryoDamage, [.atkCrit], ["Golden Troupe", "Blizzard Strayer"]),
    RosterCharacter(
      "lohen", "Lohen", .cryoDamage, [.atkCrit],
      ["A Day Carved From Rising Winds", "Shimenawa's Reminiscence"]),
    RosterCharacter(
      "skirk", "Skirk", .cryoDamage, [.atkCrit],
      ["Finale of the Deep Galleries", "Marechaussee Hunter"]),
    RosterCharacter("aloy", "Aloy", .cryoDamage, [.atkCrit], ["Blizzard Strayer"]),
    RosterCharacter(
      "charlotte", "Charlotte", .cryoDamage, [.atkSupport],
      ["Song of Days Past", "Ocean-Hued Clam"], heals: true),
    RosterCharacter(
      "chongyun", "Chongyun", .cryoDamage, [.atkCrit], ["Blizzard Strayer", "Noblesse Oblige"]),
    RosterCharacter(
      "diona", "Diona", .cryoDamage, [.hpSupport],
      ["Noblesse Oblige", "Tenacity of the Millelith"], heals: true),
    RosterCharacter("eula", "Eula", .physicalDamage, [.atkCrit], ["Pale Flame"]),
    RosterCharacter(
      "freminet", "Freminet", .physicalDamage, [.atkCrit], ["Pale Flame", "Blizzard Strayer"]),
    RosterCharacter(
      "ganyu", "Ganyu", .cryoDamage, [.atkCrit], ["Blizzard Strayer", "Wanderer's Troupe"]),
    RosterCharacter(
      "kaeya", "Kaeya", .cryoDamage, [.atkCrit], ["Blizzard Strayer", "Emblem of Severed Fate"]),
    RosterCharacter(
      "kamisato-ayaka", "Kamisato Ayaka", .cryoDamage, [.atkCrit], ["Blizzard Strayer"]),
    RosterCharacter(
      "layla", "Layla", .cryoDamage, [.hpSupport], ["Tenacity of the Millelith", "Noblesse Oblige"]),
    RosterCharacter(
      "mika", "Mika", .cryoDamage, [.hpSupport], ["Noblesse Oblige", "Ocean-Hued Clam"], heals: true
    ),
    RosterCharacter(
      "odette", "Odette", .atkPercent, [.atkCrit],
      ["Heart of the Furnace", "Disenchantment in Deep Shadow"]),
    RosterCharacter(
      "qiqi", "Qiqi", .cryoDamage, [.atkSupport], ["Ocean-Hued Clam", "Noblesse Oblige"],
      heals: true),
    RosterCharacter(
      "rosaria", "Rosaria", .cryoDamage, [.atkCrit], ["Noblesse Oblige", "Blizzard Strayer"]),
    RosterCharacter(
      "sandrone", "Sandrone", .atkPercent, [.atkEMCrit],
      ["Disenchantment in Deep Shadow", "Gilded Dreams"]),
    RosterCharacter(
      "shenhe", "Shenhe", .cryoDamage, [.atkSupport], ["Noblesse Oblige", "Blizzard Strayer"]),
    RosterCharacter(
      "wriothesley", "Wriothesley", .cryoDamage, [.atkCrit],
      ["Marechaussee Hunter", "Blizzard Strayer"]),

    // Dendro
    RosterCharacter(
      "kinich", "Kinich", .dendroDamage, [.atkCrit], ["Obsidian Codex", "Unfinished Reverie"]),
    RosterCharacter(
      "lauma", "Lauma", .dendroDamage, [.em], ["Silken Moon's Serenade", "Deepwood Memories"]),
    RosterCharacter(
      "nefer", "Nefer", .dendroDamage, [.emCrit], ["Night of the Sky's Unveiling", "Gilded Dreams"]),
    RosterCharacter(
      "traveler-dendro", "Traveler (Dendro)", .dendroDamage, [.atkEMCrit],
      ["Deepwood Memories", "Instructor"]),
    RosterCharacter(
      "baizhu", "Baizhu", .dendroDamage, [.hpSupport],
      ["Deepwood Memories", "Ocean-Hued Clam", "Instructor"], heals: true),
    RosterCharacter("collei", "Collei", .dendroDamage, [.atkEMCrit], ["Deepwood Memories"]),
    RosterCharacter(
      "emilie", "Emilie", .dendroDamage, [.atkCrit], ["Unfinished Reverie", "Deepwood Memories"]),
    RosterCharacter(
      "kaveh", "Kaveh", .dendroDamage, [.em], ["Flower of Paradise Lost", "Deepwood Memories"]),
    RosterCharacter(
      "kirara", "Kirara", .dendroDamage, [.hpSupport],
      ["Tenacity of the Millelith", "Deepwood Memories", "Instructor"]),
    RosterCharacter(
      "tighnari", "Tighnari", .dendroDamage, [.atkEMCrit], ["Wanderer's Troupe", "Gilded Dreams"]),
    RosterCharacter(
      "yaoyao", "Yaoyao", .dendroDamage, [.hpSupport],
      ["Deepwood Memories", "Ocean-Hued Clam", "Instructor", "The Exile"], heals: true),

    // Electro
    RosterCharacter(
      "flins", "Flins", .atkPercent, [.atkEMCrit],
      ["Night of the Sky's Unveiling", "Marechaussee Hunter"]),
    RosterCharacter(
      "iansan", "Iansan", .electroDamage, [.atkSupport],
      ["Scroll of the Hero of Cinder City", "Noblesse Oblige"], heals: true),
    RosterCharacter(
      "ineffa", "Ineffa", .atkPercent, [.atkEMCrit],
      ["Aubade of Morningstar and Moon", "Silken Moon's Serenade"]),
    RosterCharacter(
      "ororon", "Ororon", .electroDamage, [.atkCrit],
      ["Scroll of the Hero of Cinder City", "Noblesse Oblige"]),
    RosterCharacter(
      "varesa", "Varesa", .electroDamage, [.atkCrit], ["Long Night's Oath", "Obsidian Codex"]),
    RosterCharacter(
      "traveler-electro", "Traveler (Electro)", .electroDamage, [.erSupport],
      ["Emblem of Severed Fate", "Noblesse Oblige"]),
    RosterCharacter(
      "alyosha", "Alyosha", .electroDamage, [.atkSupport],
      ["Heart of the Furnace", "Noblesse Oblige"], heals: true),
    RosterCharacter("beidou", "Beidou", .electroDamage, [.atkCrit], ["Emblem of Severed Fate"]),
    RosterCharacter(
      "clorinde", "Clorinde", .electroDamage, [.atkCrit],
      ["Fragment of Harmonic Whimsy", "Gladiator's Finale"]),
    RosterCharacter(
      "cyno", "Cyno", .electroDamage, [.atkEMCrit], ["Thundering Fury", "Gilded Dreams"]),
    RosterCharacter(
      "dori", "Dori", .electroDamage, [.hpSupport],
      ["Noblesse Oblige", "Tenacity of the Millelith"], heals: true),
    RosterCharacter(
      "keqing", "Keqing", .electroDamage, [.atkEMCrit], ["Thundering Fury", "Gilded Dreams"]),
    RosterCharacter(
      "kujou-sara", "Kujou Sara", .electroDamage, [.erSupport],
      ["Noblesse Oblige", "Emblem of Severed Fate"]),
    RosterCharacter(
      "lisa", "Lisa", .electroDamage, [.atkEMCrit], ["Gilded Dreams", "Thundering Fury"]),
    RosterCharacter(
      "razor", "Razor", .physicalDamage, [.atkCrit], ["Pale Flame", "Gladiator's Finale"]),
    RosterCharacter(
      "sethos", "Sethos", .electroDamage, [.emCrit], ["Wanderer's Troupe", "Gilded Dreams"]),
    RosterCharacter(
      "yae-miko", "Yae Miko", .electroDamage, [.atkEMCrit], ["Golden Troupe", "Gilded Dreams"]),

    // Geo
    RosterCharacter(
      "illuga", "Illuga", .geoDamage, [.em], ["Silken Moon's Serenade", "Noblesse Oblige"]),
    RosterCharacter(
      "kachina", "Kachina", .geoDamage, [.defCrit],
      ["Scroll of the Hero of Cinder City", "Archaic Petra"]),
    RosterCharacter(
      "linnea", "Linnea", .defPercent, [.defCrit],
      ["Husk of Opulent Dreams", "Aubade of Morningstar and Moon"]),
    RosterCharacter(
      "xilonen", "Xilonen", .geoDamage, [.defSupport],
      ["Scroll of the Hero of Cinder City", "Archaic Petra", "Instructor"], heals: true),
    RosterCharacter(
      "zibai", "Zibai", .defPercent, [.defCrit],
      ["Night of the Sky's Unveiling", "Husk of Opulent Dreams"]),
    RosterCharacter(
      "traveler-geo", "Traveler (Geo)", .geoDamage, [.atkCrit],
      ["Nighttime Whispers in the Echoing Woods"]),
    RosterCharacter(
      "albedo", "Albedo", .geoDamage, [.defCrit], ["Golden Troupe", "Husk of Opulent Dreams"]),
    RosterCharacter(
      "chiori", "Chiori", .geoDamage, [.defCrit], ["Golden Troupe", "Husk of Opulent Dreams"]),
    RosterCharacter(
      "gorou", "Gorou", .geoDamage, [.defSupport],
      ["Noblesse Oblige", "Husk of Opulent Dreams", "The Exile"]),
    RosterCharacter(
      "navia", "Navia", .geoDamage, [.atkCrit],
      ["Nighttime Whispers in the Echoing Woods", "Gladiator's Finale"]),
    RosterCharacter(
      "ningguang", "Ningguang", .geoDamage, [.atkCrit],
      ["Nighttime Whispers in the Echoing Woods", "Archaic Petra"]),
    RosterCharacter("noelle", "Noelle", .geoDamage, [.defCrit], ["Husk of Opulent Dreams"]),
    RosterCharacter(
      "yun-jin", "Yun Jin", .geoDamage, [.defSupport],
      ["Husk of Opulent Dreams", "Noblesse Oblige"]),
    RosterCharacter(
      "zhongli", "Zhongli", .geoDamage, [.hpSupport],
      ["Tenacity of the Millelith", "Archaic Petra", "Instructor"]),

    // Hydro
    RosterCharacter(
      "aino", "Aino", .hydroDamage, [.em], ["Silken Moon's Serenade", "Noblesse Oblige"]),
    RosterCharacter(
      "columbina", "Columbina", .hydroDamage, [.hpCrit],
      ["Silken Moon's Serenade", "Aubade of Morningstar and Moon"]),
    RosterCharacter(
      "dahlia", "Dahlia", .hydroDamage, [.hpSupport],
      ["Noblesse Oblige", "Scroll of the Hero of Cinder City"]),
    RosterCharacter(
      "mualani", "Mualani", .hydroDamage, [.hpEMCrit], ["Obsidian Codex", "Heart of Depth"]),
    RosterCharacter(
      "traveler-hydro", "Traveler (Hydro)", .hydroDamage, [.hpCrit], ["Heart of Depth"]),
    RosterCharacter(
      "barbara", "Barbara", .hydroDamage, [.hpSupport], ["Ocean-Hued Clam", "Maiden Beloved"],
      heals: true),
    RosterCharacter(
      "candace", "Candace", .hydroDamage, [.hpSupport],
      ["Noblesse Oblige", "Tenacity of the Millelith"]),
    RosterCharacter(
      "kamisato-ayato", "Kamisato Ayato", .hydroDamage, [.atkCrit],
      ["Echoes of an Offering", "Heart of Depth"]),
    RosterCharacter(
      "mona", "Mona", .hydroDamage, [.erCrit], ["Emblem of Severed Fate", "Noblesse Oblige"]),
    RosterCharacter(
      "nilou", "Nilou", .hydroDamage, [.hpSupport],
      ["Tenacity of the Millelith", "Vourukasha's Glow"]),
    RosterCharacter(
      "sigewinne", "Sigewinne", .hydroDamage, [.hpSupport],
      ["Song of Days Past", "Ocean-Hued Clam"], heals: true),
    RosterCharacter(
      "tartaglia", "Tartaglia", .hydroDamage, [.atkCrit], ["Nymph's Dream", "Heart of Depth"]),
    RosterCharacter(
      "vodyanitsa", "Vodyanitsa", .hydroDamage, [.hpSupport],
      ["Tenacity of the Millelith", "Scroll of the Hero of Cinder City"], heals: true),

    // Pyro
    RosterCharacter(
      "durin", "Durin", .pyroDamage, [.atkCrit],
      ["A Day Carved From Rising Winds", "Gilded Dreams"]),
    RosterCharacter(
      "mavuika", "Mavuika", .pyroDamage, [.atkEMCrit],
      ["Obsidian Codex", "Scroll of the Hero of Cinder City"]),
    RosterCharacter(
      "traveler-pyro", "Traveler (Pyro)", .pyroDamage, [.atkCrit],
      ["Scroll of the Hero of Cinder City"]),
    RosterCharacter("amber", "Amber", .pyroDamage, [.atkEMCrit], ["Crimson Witch of Flames"]),
    RosterCharacter(
      "arlecchino", "Arlecchino", .pyroDamage, [.atkCrit],
      ["Fragment of Harmonic Whimsy", "Gladiator's Finale"]),
    RosterCharacter(
      "chevreuse", "Chevreuse", .pyroDamage, [.hpSupport],
      ["Noblesse Oblige", "Tenacity of the Millelith"], heals: true),
    RosterCharacter(
      "dehya", "Dehya", .pyroDamage, [.hpCrit, .atkCrit],
      ["Emblem of Severed Fate", "Vermillion Hereafter"]),
    RosterCharacter(
      "diluc", "Diluc", .pyroDamage, [.atkEMCrit],
      ["Crimson Witch of Flames", "Gladiator's Finale"]),
    RosterCharacter(
      "gaming", "Gaming", .pyroDamage, [.atkEMCrit],
      ["Marechaussee Hunter", "Crimson Witch of Flames"]),
    RosterCharacter(
      "hu-tao", "Hu Tao", .pyroDamage, [.hpEMCrit],
      ["Crimson Witch of Flames", "Shimenawa's Reminiscence"]),
    RosterCharacter("klee", "Klee", .pyroDamage, [.atkEMCrit], ["Crimson Witch of Flames"]),
    RosterCharacter("lyney", "Lyney", .pyroDamage, [.atkCrit], ["Marechaussee Hunter"]),
    RosterCharacter(
      "nicole", "Nicole", .pyroDamage, [.atkSupport],
      ["Celestial Gift", "Scroll of the Hero of Cinder City"]),
    RosterCharacter(
      "thoma", "Thoma", .pyroDamage, [.hpSupport, .em],
      ["Tenacity of the Millelith", "Flower of Paradise Lost"]),
    RosterCharacter(
      "xinyan", "Xinyan", .physicalDamage, [.atkCrit], ["Pale Flame", "Noblesse Oblige"]),
    RosterCharacter(
      "yanfei", "Yanfei", .pyroDamage, [.atkEMCrit],
      ["Crimson Witch of Flames", "Wanderer's Troupe"]),
    RosterCharacter(
      "yoimiya", "Yoimiya", .pyroDamage, [.atkEMCrit],
      ["Shimenawa's Reminiscence", "Echoes of an Offering"]),
  ]
}
