# Artifact grading: approach

Date: 2026-10-22
Status: direction agreed with the user. Steps 1 and 2 are implemented; the rest is planned.

This page records the research behind the grading direction, the decisions the
user made, and the work order. It supersedes the "no keep/discard threshold"
stance in the [evaluation proposal](evaluation-design.md) and
[next features](next-features-plan.md). Grading never acts in the game; its
verdicts are advice.

## Questions to answer

1. Is this artifact worth keeping?
2. Is it worth leveling, and to which checkpoint?
3. How does it compare with artifacts already saved?
4. Which characters is it good for?
5. If it is off-set, is it a good off-piece?
6. Which saved pieces are safe to use as fodder?

## Decisions (2026-10-22)

- Show a clear verdict at a glance: Keep, Level to +N, Review, or Fodder, with
  one reason. Verdicts are advice only.
- Cover all characters, not only the 15 reviewed roles. There is no ownership
  filter, so keep rules must be quality-based. "Someone could use this" is true
  of almost any piece with two useful substats and is not a keep reason.
- Community draft weights may be used locally as a starting point. They are
  unlicensed: generated data stays in the gitignored `local/` directory and is
  never committed or distributed.

## Research summary

Sources were read on 2026-10-22. The game was at version 7.1.

- **Genshin Optimizer Upgrade Optimizer**
  ([`libs/gi/upopt`](https://github.com/frzyc/genshin-optimizer)): for one
  character, swaps each candidate into the equipped build and reports the
  probability of improving the target and the average gain, sorted by their
  product. It enumerates roll outcomes and linearizes the damage formula. It
  needs the full inventory, a team, and a target, and works one character at a
  time. An account-wide version is an open request; nothing in GO answers "does
  this help anyone".
- **ideless/artifact** (dormant since 2023) is the closest prior art. Its sorts
  map onto the questions above: expected weighted rolls at +20; a count of
  same-slot, same-main pieces that beat it on every non-flat substat; the chance
  that none of the next 100 drops of that kind beat it (200 for off-pieces);
  and the chance it beats the equipped piece.
- **Heuristics that mislead:** Crit Value alone (Akasha's FAQ calls it naive),
  roll value over every substat, "max roll value" treated as an expectation,
  0–100 scores with arbitrary weights, and Akasha percentiles, which describe
  showcased builds rather than inventories.
- **Game mechanics:** domain drops start with four lines 20% of the time;
  bosses and the Strongbox 34%. New-line weights are flat stats 6, HP%, ATK%,
  DEF%, ER and EM 4, Crit Rate and Crit DMG 3. Main-stat odds are in the
  [Fandom distribution page](https://genshin-impact.fandom.com/wiki/Artifact/Distribution)
  and GO's constants. Reshaping (5.7) moves rolls on a +20 piece into two chosen
  substats, so a +20 piece with a good main stat and two useful substat types
  keeps value despite poor rolls. The Transmuter makes common main stats easier
  to replace. The bag cap is 2,700 from 7.0, per the wiki's change history.
- **Leveling cost:** feeding a leveled piece returns 80% of its spent EXP, and
  +16 to +20 costs about as much as +0 to +16
  ([KQM](https://keqingmains.com/misc/artifacts/)). Early checkpoints are cheap
  gambles; the last one is not. No widely cited stopping analysis was found.
- **Inventory export:** Irminsul is the current community exporter and has a
  macOS build, but it reads the local game client's traffic. The user plays
  through GeForce NOW, so it is not expected to work (untested). The whole bag
  has to come from this app's own OCR.

## Approach

### 1. Enumerate final substats, not one profile's score — implemented

`RollOutcomes` enumerates every ordinary +20 outcome as final roll units per
substat line. A +0 four-line piece has 7,592 distinct outcomes; enumeration
takes about 5 ms in a release build, and scoring 150 profiles about 10 ms.
`Potential.evaluate` scores this enumeration and accepts a shared one;
`CharacterAssessment` enumerates once per artifact. Existing distributions are
unchanged; tests compare them with the previous scalar convolution.

This enables questions across profiles that a single-profile score histogram
cannot answer, such as the chance of a strong result for any character, and
later ER handling that stops counting past a requirement.

### 2. Intrinsic quality: rarity among possible drops — implemented

`DropRarity` computes, for one profile, slot, and main stat, the exact final
+20 score distribution of a new drop: main-stat odds and substat appearance
weights from Genshin Optimizer's constants, the domain's 20% four-line start
(34% for bosses and the Strongbox), and uniform roll tiers. A three-line start
reveals its fourth line by the same weighted draw as a four-line start, so
both share one set of final lines and differ only in the number of upgrades. A
seeded simulation of the actual drop process agrees within half a percentage
point. A table takes under 1 ms and is cached per slot, main stat, and weights.

A piece's share is the fraction of new drops finishing at or above its score.
Tiers come from the share; every reviewed role is graded. A piece is ungraded
only when no core substat can appear on it or when it has no final score or
forecast.

The cutoffs were fitted to the 15 cells reviewed by hand. Those hand cutoffs
correspond to consistent shares across very different cells:

| Hand cutoff | Share of new drops reaching it | Chosen bound |
| --- | --- | --- |
| C | 43–65% | 50% |
| B | 11–17% | 15% |
| A | 0.6–1.3% | 1% |
| S | 0.008–0.035% | 0.05% |

With these bounds, the derived B, A, and S cutoffs fall within 0.3 rolls of the
hand cutoffs in every cell; C differs by up to half a roll, stricter on flowers
and plumes and looser on sands and HP% goblets. The original proposal of S top
1% and A top 5% would have been far more lenient than the reviewed anchors.
Tests keep every hand anchor within one tier of its hand label.

`expectedDropsToBeat` gives the expected five-star domain drops, counting both
of the domain's sets, before a piece of the same set, slot, and main stat
finishes strictly higher: two sets per domain, five slots, the main-stat odds,
and the share above. An EM goblet of the wanted set alone is 1 in 400 domain
drops. The dashboard and overlay show the share and this estimate.

Rarity is not value. A rare piece for an unwanted role is still unused; the
account checks below cover that. Rarity is comparable across characters, so
it can order the shortlist in step 3.

### 3. Account value: margin over saved pieces

- Rank and chance to beat the best saved piece, already implemented.
- Chance to beat the equipped piece, once equipped data is available.
- Dominance count: how many saved pieces with the same slot and main stat beat
  this one on every non-flat substat. Three or more makes it fodder whatever
  the weights say.

### 4. Verdicts

| Question | Rule (defaults to tune) |
| --- | --- |
| Keep | A or better for some stat-profile group; or top few in a group's pool; or a rare main stat with nothing better saved; or a +20 piece worth reshaping |
| Fodder | Beaten on every stat by three or more saved pieces, and no keep reason |
| Review | Neither of the above |
| Level | Exact chance of becoming a keeper, against a bar that rises with each checkpoint |
| Off-piece | Rank across all sets, and margin over the best on-set piece in that slot |

Group roles with the same stat profile, such as the HP% and Crit roles, and
count a piece once per group, not once per character.

### 5. Weights

The draft (`fallumina/Genshin-Artifact-Rater`, 142 roles through 7.0) records
which stats matter, not how much. Its values are 0, 2, 4, 6, 8, or 10, and its
flat-stat values are wrong in damage terms: Furina's flat HP is 8, but one flat
HP roll is about a third of an HP% roll at her base HP. Use it as follows:

1. **Exact from game data:** flat stats relative to their percentage stat
   using character base stats from Genshin Optimizer (MIT) and an assumed
   weapon base ATK; equal Crit Rate and Crit DMG per roll; ER as a requirement
   rather than a weight.
2. **Which stats count:** three levels (core 1, secondary 0.5, none 0) from
   the draft, checked per character against one guide with a recorded link.
   Disagreements are flagged for the user.
3. **Damage-derived weights**, from an offline script on GO's formulas at a
   standard build, only for characters where the weight source changes
   verdicts. Running verdicts under the draft and reviewed weights marks those
   close calls.

`tools/weights/` converts the draft into `local/role-weights-draft.json` and a
review report. The output is local-only.

## Work order

1. Final-substat enumeration. Done.
2. Rarity and replacement cost; rarity-derived tiers checked against the 15
   calibrated cells. Done.
3. Stat-profile groups and Keep / Level verdicts in the overlay.
4. Whole-bag OCR scan of all five-star levels, then the fodder list.
5. Reviewed weights for all characters; damage-derived weights for close calls.

Open questions: the leveling bar per checkpoint;
whether the inventory card's equipped-by line can be read reliably; how to
model reshaped and Transmuter pieces, which the ordinary model excludes.
