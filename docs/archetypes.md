# Character archetypes

Date: 2026-10-25. Dataset `archetypes-2026-10-25.1`, game version 7.1.

Loupe grades a piece by how rare it is among new drops of its slot and main stat, under a
character's scored stats. That answer is the same for every character with the same scored stats,
so characters are grouped into archetypes instead of reviewed one build at a time. Each character
records only what changes advice: its archetypes, the goblet it uses, and its four-piece sets.

The 15 roles reviewed on 2026-09-27 are unchanged and take precedence. Each matches exactly one
archetype, and a test checks that adding archetype roles does not change their advice. Every other
role is marked in the app as an archetype role that was not individually reviewed.

Code: `Sources/LoupeCore/Archetypes.swift` (definitions) and `Sources/LoupeCore/Roster.swift`
(characters). The table below is generated from `Roster.swift`.

## Archetypes

Scored stats count toward the grade, one point per roll. Utility stats are shown but not scored.
"DMG" in the goblet column means the character's own DMG Bonus goblet (see the table below).
\*Healing Bonus circlets fit only characters marked as healers in `Roster.swift`; CRIT Rate
circlets are for supports on Favonius weapons.

| Archetype | Scored | Utility | Sands | Goblet | Circlet |
| --- | --- | --- | --- | --- | --- |
| ATK crit damage | ATK%, CRIT Rate, CRIT DMG | ER | ATK%, ER | DMG | CRIT Rate, CRIT DMG |
| ATK reaction damage | ATK%, EM, CRIT Rate, CRIT DMG | ER | ATK%, EM, ER | DMG | CRIT Rate, CRIT DMG |
| HP crit damage | HP%, CRIT Rate, CRIT DMG | ER | HP%, ER | DMG, HP% | CRIT Rate, CRIT DMG |
| HP reaction damage | HP%, EM, CRIT Rate, CRIT DMG | ER | HP%, EM | DMG | CRIT Rate, CRIT DMG |
| DEF crit damage | DEF%, CRIT Rate, CRIT DMG | ER, ATK% | DEF%, ER | DMG | CRIT Rate, CRIT DMG |
| EM crit damage | EM, CRIT Rate, CRIT DMG | ER, ATK% | EM, ATK% | DMG, EM | CRIT Rate, CRIT DMG, EM |
| Energy-scaling Burst damage | ER, ATK%, CRIT Rate, CRIT DMG | none | ER, ATK% | DMG, ATK% | CRIT Rate, CRIT DMG |
| EM reaction support | EM | ER | EM, ER | EM | EM |
| HP healer / shield / buffer | HP% | ER, HP | HP%, ER | HP% | HP%, CRIT Rate, Healing* |
| ATK healer / buffer | ATK%, ER | ATK, CRIT Rate | ATK%, ER | ATK% | ATK%, CRIT Rate, Healing* |
| DEF shield / buffer | DEF%, ER | DEF, CRIT Rate | DEF%, ER | DEF% | DEF%, CRIT Rate, Healing* |
| Energy / Burst support | ER, CRIT Rate | ATK%, HP% | ER | DMG, ATK%, HP% | CRIT Rate, ATK%, HP% |

Choices worth knowing:

- **EM for reaction carriers.** Vaporize and Melt carriers such as Diluc, Hu Tao, Klee and Yoimiya
  score EM. Some community lists treat EM as secondary for them; guides commonly recommend EM
  sands, so it counts here.
- **Lunar reactions** (Nod-Krai) scale on EM and can crit, with a smaller bonus from the enabler's
  ATK or DEF. Flins and Ineffa are ATK reaction damage, Nefer is EM crit damage, and Zibai and
  Linnea are DEF crit damage.
- **Stellar reactions** (Snezhnaya) carriers Vesna, Odette and Sandrone use ATK% goblets, per the
  guides below.
- **Supports score a second stat.** ATK and DEF supports also score ER, and Energy supports score
  CRIT Rate for the Favonius weapons guides pair them with. With one scored stat, a piece whose
  main stat is that stat has nothing left to grade, and Loupe keeps such pieces while fewer than
  three are saved: on an empty inventory every sands would be leveled. HP and EM supports keep one
  scored stat because the reviewed Kokomi, Bennett, Kuki, Kazuha and Sucrose roles define them.
- **Several archetypes for one character** when guides split clearly: Raiden (Hyperbloom and
  Burst), Venti, Heizou, Ifa and Lan Yan (Swirl and damage), Thoma, Dehya.

## Characters

| Character | Archetypes | DMG goblet | Sets, preferred first |
| --- | --- | --- | --- |
| Aino | EM reaction support | — | Silken Moon's Serenade; Noblesse Oblige |
| Albedo | DEF crit | Geo DMG | Golden Troupe; Husk of Opulent Dreams |
| Alhaitham | EM crit (first is the reviewed role) | Dendro DMG | Gilded Dreams; Deepwood Memories |
| Aloy | ATK crit | Cryo DMG | Blizzard Strayer |
| Alyosha | ATK support; heals | — | Heart of the Furnace; Noblesse Oblige |
| Amber | ATK reaction | Pyro DMG | Crimson Witch of Flames |
| Arataki Itto | DEF crit (first is the reviewed role) | Geo DMG | Husk of Opulent Dreams |
| Arlecchino | ATK crit | Pyro DMG | Fragment of Harmonic Whimsy; Gladiator's Finale |
| Baizhu | HP support; heals | — | Deepwood Memories; Ocean-Hued Clam |
| Barbara | HP support; heals | — | Ocean-Hued Clam; Maiden Beloved |
| Beidou | ATK crit | Electro DMG | Emblem of Severed Fate |
| Bennett | HP support (first is the reviewed role) | — | Noblesse Oblige; Scroll of the Hero of Cinder City |
| Candace | HP support | — | Noblesse Oblige; Tenacity of the Millelith |
| Charlotte | ATK support; heals | — | Song of Days Past; Ocean-Hued Clam |
| Chasca | ATK crit | ATK% | Obsidian Codex; Marechaussee Hunter |
| Chevreuse | HP support; heals | — | Noblesse Oblige; Tenacity of the Millelith |
| Chiori | DEF crit | Geo DMG | Golden Troupe; Husk of Opulent Dreams |
| Chongyun | ATK crit | Cryo DMG | Blizzard Strayer; Noblesse Oblige |
| Citlali | EM reaction support | — | Scroll of the Hero of Cinder City; Tenacity of the Millelith |
| Clorinde | ATK crit | Electro DMG | Fragment of Harmonic Whimsy; Gladiator's Finale |
| Collei | ATK reaction | Dendro DMG | Deepwood Memories |
| Columbina | HP crit | Hydro DMG | Silken Moon's Serenade; Aubade of Morningstar and Moon |
| Cyno | ATK reaction | Electro DMG | Thundering Fury; Gilded Dreams |
| Dahlia | HP support | — | Noblesse Oblige; Scroll of the Hero of Cinder City |
| Dehya | HP crit, ATK crit | Pyro DMG | Emblem of Severed Fate; Vermillion Hereafter |
| Diluc | ATK reaction | Pyro DMG | Crimson Witch of Flames; Gladiator's Finale |
| Diona | HP support; heals | — | Noblesse Oblige; Tenacity of the Millelith |
| Dori | HP support; heals | — | Noblesse Oblige; Tenacity of the Millelith |
| Durin | ATK crit | Pyro DMG | A Day Carved From Rising Winds; Gilded Dreams |
| Emilie | ATK crit | Dendro DMG | Unfinished Reverie; Deepwood Memories |
| Escoffier | ATK crit | Cryo DMG | Golden Troupe; Blizzard Strayer |
| Eula | ATK crit | Physical DMG | Pale Flame |
| Faruzan | Energy support | Anemo DMG | Tenacity of the Millelith; Noblesse Oblige |
| Fischl | ATK reaction (first is the reviewed role) | Electro DMG | Golden Troupe; Gilded Dreams |
| Flins | ATK reaction | ATK% | Night of the Sky's Unveiling; Marechaussee Hunter |
| Freminet | ATK crit | Physical DMG | Pale Flame; Blizzard Strayer |
| Furina | HP crit (first is the reviewed role) | Hydro DMG | Golden Troupe; Tenacity of the Millelith |
| Gaming | ATK reaction | Pyro DMG | Marechaussee Hunter; Crimson Witch of Flames |
| Ganyu | ATK crit | Cryo DMG | Blizzard Strayer; Wanderer's Troupe |
| Gorou | DEF support | — | Noblesse Oblige; Husk of Opulent Dreams |
| Hu Tao | HP reaction | Pyro DMG | Crimson Witch of Flames; Shimenawa's Reminiscence |
| Iansan | ATK support; heals | — | Scroll of the Hero of Cinder City; Noblesse Oblige |
| Ifa | EM reaction support, ATK crit | Anemo DMG | Viridescent Venerer; Obsidian Codex |
| Illuga | EM reaction support | — | Silken Moon's Serenade; Noblesse Oblige |
| Ineffa | ATK reaction | ATK% | Aubade of Morningstar and Moon; Silken Moon's Serenade |
| Jahoda | ATK support; heals | — | Viridescent Venerer; Silken Moon's Serenade |
| Jean | ATK support; heals | — | Viridescent Venerer; Ocean-Hued Clam |
| Kachina | DEF crit | Geo DMG | Scroll of the Hero of Cinder City; Archaic Petra |
| Kaedehara Kazuha | EM reaction support (first is the reviewed role) | — | Viridescent Venerer |
| Kaeya | ATK crit | Cryo DMG | Blizzard Strayer; Emblem of Severed Fate |
| Kamisato Ayaka | ATK crit | Cryo DMG | Blizzard Strayer |
| Kamisato Ayato | ATK crit | Hydro DMG | Echoes of an Offering; Heart of Depth |
| Kaveh | EM reaction support | — | Flower of Paradise Lost; Deepwood Memories |
| Keqing | ATK reaction | Electro DMG | Thundering Fury; Gilded Dreams |
| Kinich | ATK crit | Dendro DMG | Obsidian Codex; Unfinished Reverie |
| Kirara | HP support | — | Tenacity of the Millelith; Deepwood Memories |
| Klee | ATK reaction | Pyro DMG | Crimson Witch of Flames |
| Kujou Sara | Energy support | Electro DMG | Noblesse Oblige; Emblem of Severed Fate |
| Kuki Shinobu | EM reaction support (first is the reviewed role) | — | Flower of Paradise Lost; Gilded Dreams |
| Lan Yan | ATK support, EM reaction support | — | Viridescent Venerer; Scroll of the Hero of Cinder City |
| Lauma | EM reaction support | — | Silken Moon's Serenade; Deepwood Memories |
| Layla | HP support | — | Tenacity of the Millelith; Noblesse Oblige |
| Linnea | DEF crit | DEF% | Husk of Opulent Dreams; Aubade of Morningstar and Moon |
| Lisa | ATK reaction | Electro DMG | Gilded Dreams; Thundering Fury |
| Lohen | ATK crit | Cryo DMG | A Day Carved From Rising Winds; Shimenawa's Reminiscence |
| Lynette | ATK crit | Anemo DMG | Viridescent Venerer |
| Lyney | ATK crit | Pyro DMG | Marechaussee Hunter |
| Mavuika | ATK reaction | Pyro DMG | Obsidian Codex; Scroll of the Hero of Cinder City |
| Mika | HP support; heals | — | Noblesse Oblige; Ocean-Hued Clam |
| Mona | Energy-scaling Burst | Hydro DMG | Emblem of Severed Fate; Noblesse Oblige |
| Mualani | HP reaction | Hydro DMG | Obsidian Codex; Heart of Depth |
| Nahida | EM crit (first is the reviewed role) | Dendro DMG | Deepwood Memories; Gilded Dreams |
| Navia | ATK crit | Geo DMG | Nighttime Whispers in the Echoing Woods; Gladiator's Finale |
| Nefer | EM crit | Dendro DMG | Night of the Sky's Unveiling; Gilded Dreams |
| Neuvillette | HP crit (first is the reviewed role) | Hydro DMG | Marechaussee Hunter; Heart of Depth |
| Nicole | ATK support | — | Celestial Gift; Scroll of the Hero of Cinder City |
| Nilou | HP support | — | Tenacity of the Millelith; Vourukasha's Glow |
| Ningguang | ATK crit | Geo DMG | Nighttime Whispers in the Echoing Woods; Archaic Petra |
| Noelle | DEF crit | Geo DMG | Husk of Opulent Dreams |
| Odette | ATK crit | ATK% | Heart of the Furnace; Disenchantment in Deep Shadow |
| Ororon | ATK crit | Electro DMG | Scroll of the Hero of Cinder City; Noblesse Oblige |
| Prune | ATK support | — | Viridescent Venerer; Celestial Gift |
| Qiqi | ATK support; heals | — | Ocean-Hued Clam; Noblesse Oblige |
| Raiden Shogun | EM reaction support, Energy-scaling Burst (first is the reviewed role) | Electro DMG | Emblem of Severed Fate |
| Razor | ATK crit | Physical DMG | Pale Flame; Gladiator's Finale |
| Rosaria | ATK crit | Cryo DMG | Noblesse Oblige; Blizzard Strayer |
| Sandrone | ATK reaction | ATK% | Disenchantment in Deep Shadow; Gilded Dreams |
| Sangonomiya Kokomi | HP support (first is the reviewed role) | — | Ocean-Hued Clam; Tenacity of the Millelith |
| Sayu | EM reaction support | — | Viridescent Venerer |
| Sethos | EM crit | Electro DMG | Wanderer's Troupe; Gilded Dreams |
| Shenhe | ATK support | — | Noblesse Oblige; Blizzard Strayer |
| Shikanoin Heizou | ATK crit, EM reaction support | Anemo DMG | Viridescent Venerer |
| Sigewinne | HP support; heals | — | Song of Days Past; Ocean-Hued Clam |
| Skirk | ATK crit | Cryo DMG | Finale of the Deep Galleries; Marechaussee Hunter |
| Sucrose | EM reaction support (first is the reviewed role) | — | Viridescent Venerer; Deepwood Memories |
| Tartaglia | ATK crit | Hydro DMG | Nymph's Dream; Heart of Depth |
| Thoma | HP support, EM reaction support | — | Tenacity of the Millelith; Flower of Paradise Lost |
| Tighnari | ATK reaction | Dendro DMG | Wanderer's Troupe; Gilded Dreams |
| Traveler (Anemo) | EM reaction support | — | Viridescent Venerer |
| Traveler (Dendro) | ATK reaction | Dendro DMG | Deepwood Memories |
| Traveler (Electro) | Energy support | Electro DMG | Emblem of Severed Fate; Noblesse Oblige |
| Traveler (Geo) | ATK crit | Geo DMG | Nighttime Whispers in the Echoing Woods |
| Traveler (Hydro) | HP crit | Hydro DMG | Heart of Depth |
| Traveler (Pyro) | ATK crit | Pyro DMG | Scroll of the Hero of Cinder City |
| Varesa | ATK crit | Electro DMG | Long Night's Oath; Obsidian Codex |
| Varka | ATK crit | ATK% | A Day Carved From Rising Winds; Shimenawa's Reminiscence |
| Venti | EM reaction support, ATK crit | Anemo DMG | Viridescent Venerer |
| Vesna | ATK crit | ATK% | Scarlet Proof; Viridescent Venerer |
| Vodyanitsa | HP support; heals | — | Tenacity of the Millelith; Scroll of the Hero of Cinder City |
| Wanderer | ATK crit | Anemo DMG | Desert Pavilion Chronicle; Shimenawa's Reminiscence |
| Wriothesley | ATK crit | Cryo DMG | Marechaussee Hunter; Blizzard Strayer |
| Xiangling | ATK reaction (first is the reviewed role) | Pyro DMG | Emblem of Severed Fate; Crimson Witch of Flames |
| Xianyun | ATK support; heals | — | Song of Days Past; Viridescent Venerer |
| Xiao | ATK crit | Anemo DMG | Vermillion Hereafter; Desert Pavilion Chronicle |
| Xilonen | DEF support; heals | — | Scroll of the Hero of Cinder City; Archaic Petra |
| Xingqiu | ATK crit (first is the reviewed role) | Hydro DMG | Emblem of Severed Fate; Noblesse Oblige |
| Xinyan | ATK crit | Physical DMG | Pale Flame; Noblesse Oblige |
| Yae Miko | ATK reaction | Electro DMG | Golden Troupe; Gilded Dreams |
| Yanfei | ATK reaction | Pyro DMG | Crimson Witch of Flames; Wanderer's Troupe |
| Yaoyao | HP support; heals | — | Deepwood Memories; Ocean-Hued Clam |
| Yelan | HP crit (first is the reviewed role) | Hydro DMG | Emblem of Severed Fate; Nymph's Dream |
| Yoimiya | ATK reaction | Pyro DMG | Shimenawa's Reminiscence; Echoes of an Offering |
| Yumemizuki Mizuki | EM reaction support | — | Viridescent Venerer; Gilded Dreams |
| Yun Jin | DEF support | — | Husk of Opulent Dreams; Noblesse Oblige |
| Zhongli | HP support | — | Tenacity of the Millelith; Archaic Petra |
| Zibai | DEF crit | DEF% | Night of the Sky's Unveiling; Husk of Opulent Dreams |

Sets belong to the character and apply to each of its archetype roles; a reviewed role keeps its
own reviewed sets. "DMG goblet" is the goblet the damage archetypes use; "—" means the character
has only support archetypes.

Not assigned yet: "Somnia", which Genshin Optimizer lists but no source could confirm, and the Cryo
Traveler, whose build could not be confirmed. Four-star sets are left out because Loupe grades
five-star pieces only.

## Sources

Characters released before 5.0 were assigned from general knowledge of their standard builds. For
characters from 5.0 onward, builds were checked on 2026-10-25 against KQM quick guides
(`keqingmains.com/q/<name>-quickguide/`), with genshin.gg, genshin-builds.com, Pocket Tactics and
Icy Veins as second sources. Confidence was lower where sources disagree or there was only one:
Lan Yan, Yumemizuki Mizuki, Iansan, Ifa, Escoffier, Ineffa, Aino, Durin, Jahoda, Columbina, Lohen,
Linnea, Vesna, Odette, Alyosha and Prune.

Character names, elements and set names come from Genshin Optimizer (MIT) at commit `7d1fcb7`.
No data from unlicensed community drafts is used; one was compared locally only to flag
disagreements.

## What archetypes do not model

- A character's own ER requirement, weapon, constellations and team.
- Differences within an archetype, such as one HP crit character valuing ER more than another.
  Scores use one point per scored roll, as for the reviewed roles.
- Which of a character's archetypes you actually play. Every listed archetype counts, so verdicts
  are more generous than with the 15 reviewed roles alone. Check verdict defaults on a scanned
  inventory before relying on Fodder.

Verdicts on 1,500 random domain drops per row, with no saved inventory:

| Roles | +0 leveled: flower / sands / goblet / circlet | +20 Keep / Review / Fodder: flower; goblet |
| --- | --- | --- |
| 15 reviewed | 12% / 52% / 30% / 40% | 3 / 90 / 5%; 25 / 9 / 65% |
| All archetype roles | 28% / 59% / 59% / 58% | 5 / 94 / 0%; 32 / 43 / 23% |

Goblets level more because elemental goblets now have users; before, most had none. A finished
flower is no longer in the bottom half of new drops for every role, so without saved pieces to
compare it ends as Review; Fodder for finished pieces now comes from the saved inventory.

Disputed cases can be settled with damage-derived weights from Genshin Optimizer's formulas, as
the grading approach describes.

## Changing an assignment

Edit the character's line in `Roster.swift`, regenerate the table above, and run `make check`.
Tests check that set names exist, IDs are unique, every archetype is used, and the reviewed roles
are unchanged.
