# Five-character assessment pilot

This records the original pilot. Current coverage includes
[15 reviewed roles](character-coverage-expansion.md) and
[11 additional calibrated combinations](tier-expansion-review.md).
The original four grading rules below are unchanged.

Reviewed 2026-09-26. Dataset: `pilot-2026-09-26.1`. Calibration:
`experimental-pilot-2026-09-26.1`.

## Integration contract

```swift
let matches = CharacterAssessment.evaluate(
  artifact, inventory: savedArtifacts, scope: .offPiece, excluding: linkedSavedID)
```

The synchronous, IO-free API returns `[CharacterMatch]`, with one role per
character in stable character-ID order. Call it away from the UI thread.
Cancellation is checked between roles; an in-flight `Potential` calculation
finishes normally. Callers must discard results from cancelled or stale work.

Each Sendable match exposes `characterID`, `characterName`, `roleID`,
`roleName`, `usefulStats`, `secondaryStats`, `profile`, `setFit`, `conditions`,
`reasons`, `potential`, `potentialUnavailableReason`, and optional `grades`.
`role` includes main-stat eligibility, sets, and source metadata. Results have
no public initializer; obtain them from the engine.

`CharacterGradeSummary` exposes optional `current`, `p50`, `p90`,
`bestPossible`, `chanceOfAOrBetter`, plus `calibrationID` and `experimental`.
Tier cases `.s`, `.a`, `.b`, `.c`, `.d` have uppercase raw-value labels.
Show "Experimental" beside every tier. No summary means "Ungraded".
An unfinished piece has no current tier because these cells assume a +20
main stat. Show its median +20 tier, with P90 and best possible separately.
At +20, all supported ordinary projections collapse to the actual tier.

All projections and account odds use the same fixed role profile. Grade
calculation never reads inventory. Saved comparisons retain `Potential`'s
same-slot, exact-main, +20 pool and selected set scope. Pass the linked saved
ID through `excluding:`; distinct copies remain distinct benchmarks. No
benchmarks means unavailable account odds, not zero odds. Inventory may be
incomplete.

Use `CharacterAssessment.datasetVersion`, `calibrationVersion`, and
`coverageDescription` for display and diagnostics. Use
`CharacterRoles.noMatchDescription` for empty results. Manual profiles remain
separate and available outside this pilot.

## Coverage and evidence

This local typed dataset contains five roles, including unowned characters.
Main-stat eligibility precedes set fit. All legal off-pieces remain eligible.
An on-set result does not establish an active four-piece bonus; an off-piece
assumes the other four slots can supply it. These are potential users, not a
strongest-to-weakest ranking. A compatible main alone is not a strong match.

The following original factual records summarize only the sections checked on
2026-09-26. Flower and plume mains are fixed. Listed sands, goblet, and circlet
choices are role eligibility, not a complete-build recommendation.

| Role | Sands; goblet; circlet | Core screen and set context | Source |
| --- | --- | --- | --- |
| Furina, off-field HP damage / Burst support | HP% or ER; HP% or Hydro; Crit | HP% and both Crit stats. Golden Troupe for personal damage; Tenacity is a conditional ATK-support alternative. | [Prydwen, Build and Energy](https://www.prydwen.gg/genshin-impact/characters/furina), updated 2026-09-25 |
| Itto, on-field DEF damage | DEF%; Geo; Crit | DEF% and both Crit stats. Husk is preferred. ATK% and ER remain utility. | [KQM, Artifacts](https://keqingmains.com/q/itto-quickguide/), version 5.6; set calculations 3.1 |
| Xiangling, reverse Vaporize Burst damage | ER, EM, or ATK%; Pyro; Crit | ATK%, EM, and both Crit stats under reaction ownership. Emblem preferred; Crimson Witch and Gilded are reaction alternatives. | [KQM, Artifacts](https://keqingmains.com/q/xiangling-quickguide/), version 4.5 |
| Kuki Shinobu, Hyperbloom trigger | EM; EM; EM | EM core. Flower of Paradise Lost preferred; Gilded alternative. ER and HP% are utility, not reasons to sacrifice EM. | [KQM, Hyperbloom](https://keqingmains.com/q/shinobu-quickguide/), version 5.4 |
| Kokomi, on-field healer / enabler | HP% or ER; Hydro or alternative HP%; Healing Bonus | HP% core; flat HP and ER utility. Clam preferred; Tenacity conditional on team ATK benefit. Standard healing excludes both Crit stats because of her Crit Rate penalty. | [KQM, On-field healer and Flawless Strategy](https://keqingmains.com/q/kokomi-quickguide/), Luna V |

Guide priorities do not become damage coefficients. Core stats receive binary
100 weights in maximum-roll units. Secondary stats receive no numeric weight.
All conditions remain `unknown`: no full build, team, weapon, constellation,
or rotation is supplied. ER is not scored and cannot establish Burst readiness.
Crit rolls are counted without a cap, so complete-build overcap waste is not
known. Xiangling's EM screen assumes she owns reverse Vaporize reactions;
Kuki's screen assumes she triggers Hyperbloom. Neither assumption is inferred
from the card.

Excluded: Itto plunge and buff-dependent DEF goblets, Kuki Quicken/pure healing,
Kokomi off-field/Bloom, weapon-specific procs, constellation variants, newer
unreviewed equipment, and all other characters. No whole-roster claim applies.

## Reviewed experimental calibration

The parent reviewed this subset and table on 2026-09-26. These are original
heuristic review anchors, not guide thresholds, damage measurements, or a
universal roll ladder. Scores cannot rank different profiles. The engine keeps
identity ordering even when some matches have tiers.

| Exact cell | D | C | B | A | S |
| --- | --- | --- | --- | --- | --- |
| Furina / Hydro goblet | below 1.4 | 1.4 | 3.5 | 5.6 | 7.0 |
| Itto / Geo goblet | below 1.4 | 1.4 | 3.5 | 5.6 | 7.0 |
| Kuki / HP flower | below 0.7 | 0.7 | 2.1 | 3.5 | 4.9 |
| Kuki / ATK plume | below 0.7 | 0.7 | 2.1 | 3.5 | 4.9 |

Entries are inclusive lower thresholds. D means poor for this screen, C
marginal, B useful but replaceable, A strong, and S exceptional. Role conditions
still apply. A full build can change the practical value substantially.

The following legal synthetic +20 artifacts bracket every shipped transition.
All have nine substat rolls. Values retain table precision for reproducibility;
the app normally displays rounded values. Each cell uses its own fixed profile.

| Furina Hydro goblet substats | Score | Tier |
| --- | --- | --- |
| HP% 5.83, ATK 97.25, DEF 46.30, ER 6.48 | 1.0 | D |
| HP% 8.16, ATK 77.80, DEF 46.30, ER 6.48 | 1.4 | C |
| HP% 19.81, ATK 58.35, DEF 23.15, ER 6.48 | 3.4 | C |
| HP% 20.40, ATK 38.90, DEF 23.15, ER 6.48 | 3.5 | B |
| HP% 23.32, CR 5.83, DEF 46.30, ER 6.48 | 5.5 | B |
| HP% 23.32, CR 6.22, DEF 46.30, ER 6.48 | 5.6 | A |
| HP% 17.49, CR 7.78, CD 14.76, ATK 38.90 | 6.9 | A |
| HP% 17.49, CR 7.78, CD 15.54, ATK 38.90 | 7.0 | S |

For Itto's Geo goblet, replace HP% in those rows with DEF%
`7.29, 10.20, 24.78, 25.50, 29.16, 29.16, 21.87, 21.87`, respectively.
Replace flat DEF 46.30 with HP 597.50 and DEF 23.15 with HP 298.75.
The scores and labels stay the same under Itto's DEF profile. These separate
fixtures test the same proposed transitions with legal DEF rolls.

| Kuki flower substats | Score | Tier |
| --- | --- | --- |
| ATK 97.25, DEF 46.30, HP% 5.83, ER 6.48 | 0.0 | D |
| EM 16.32, ATK 97.25, DEF 46.30, HP% 5.83 | 0.7 | C |
| EM 46.62, ATK 97.25, DEF 23.15, HP% 5.83 | 2.0 | C |
| EM 48.96, ATK 77.80, DEF 23.15, HP% 5.83 | 2.1 | B |
| EM 79.26, ATK 58.35, DEF 23.15, HP% 5.83 | 3.4 | B |
| EM 81.60, ATK 38.90, DEF 23.15, HP% 5.83 | 3.5 | A |
| EM 111.89, ATK 38.90, DEF 23.15, HP% 5.83 | 4.8 | A |
| EM 114.22, ATK 38.90, DEF 23.15, HP% 5.83 | 4.9 | S |

Plume fixtures replace flat ATK with the same count of maximum flat HP rolls
(298.75 each), retaining all other stats. The zero-to-0.7 and 1.0-to-1.4
transitions use adjacent attainable values for these selected stat combinations;
there is no fabricated 0.6 EM roll or 1.3 HP% total.

The thresholds distinguish useful-roll concentration within each reviewed
cell. They do not prove these labels generalize to other mains, builds, or
damage objectives. More context-sensitive calibration requires a separate
review, not automatic interpolation.

## Failure cases and limits

- EM mains cannot roll EM substats. Kuki's EM sands, goblets, and circlets
  remain eligible and ungraded. When the main stat removes the profile's only
  core stat, `potential` is nil with an explicit reason. This also applies to
  Kokomi's HP% mains. No scalar comparison can distinguish these pieces, so
  showing zero scores with guaranteed rank ties would mislead. An EM flower
  without EM substats retains a valid zero score because EM is eligible there.
- Kokomi's Healing Bonus main remains eligible with Crit-heavy substats.
  Adding Crit leaves her score unchanged. All Kokomi cells remain ungraded:
  healing targets, ER needs, and utility require further review.
- An ER-heavy piece can meet an actual build need that this core screen omits.
  Unknown ER is always visible; neither low core tiers nor missing ER prove
  that a build should keep or discard the piece.
- Crit caps and balance require complete-build information. No cap-aware
  damage, build-readiness, or swap-improvement claim is supported.
- A low-level S ceiling is not an earned S. Current grades stay absent until
  +20; the median and ceiling never switch roles.
- Special-roll artifacts retain matching explanations but no ordinary-roll
  probabilities. Missing fourth-stat knowledge retains the existing Potential
  error. A finished calibrated artifact can still receive a current intrinsic
  tier without upgrade odds.

No guide text, images, tables, or bulk dataset were copied. This is a bounded
local factual pilot with source links. Attribution alone is not a redistribution
license. Permission review for packaged distribution or expanded collection
remains the [source-reuse gate](evaluation-design.md#source-reuse-and-approval-decisions).
No runtime guide fetch, scraper, upload, or private inventory read is involved.

## Verification

`CharacterAssessmentTests` has 20 tests (48 parameter-expanded cases). They
exercise legal on/off-set artifacts, distinct identities, wrong mains, Kokomi
Crit exclusion, conditional ER/reactions, every shipped tier boundary, useful
roll monotonicity, inventory independence and linked-ID exclusion, final point
masses, unfinished median/ceiling separation, A-or-better distribution mass,
missing fourth stats, special rules, and cancellation.

All 68 ArtifactCore tests passed in an isolated Swift scratch/cache build on
2026-09-26. The A-or-better assertion was temporarily changed from 3/16 to
4/16, failed with actual 0.1875 versus expected 0.25, and was restored before
the final green run. Scoped strict Swift formatting and ASCII/whitespace
checks passed. This work did not run the app, private recorded fixtures, or
live game checks. The no-eligible-core regression first reproduced guaranteed
rank ties on all three EM-main slots; the fix suppresses that unsupported
screen without changing ordinary event probabilities or valid zero scores.
