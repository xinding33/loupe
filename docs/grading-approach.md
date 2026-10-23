# Artifact grading: approach

Date: 2026-10-22
Status: direction agreed with the user. Step 1 is implemented; the rest is planned.

This page records the research behind the grading direction, the decisions the
user made, and the work order. It supersedes the "no keep/discard threshold"
stance in the [evaluation proposal](evaluation-design.md) and
[next features](next-features-plan.md). The app still never clicks in the game.

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

### 2. Intrinsic quality: rarity among possible drops

For each character role, slot, and main stat, compute the share of all
possible new drops that would finish at or above this piece. The published
odds make this exact: main-stat odds, the four-line start chance, new-line
weights, and the four roll tiers. Unfinished pieces use their outcome
distribution.

- Tiers derive from rarity, for example S top 1%, A top 5%, B top 20%, C top
  50%, adjustable. The 15 hand-calibrated cells become a validation check.
- Rarity is comparable across characters, so the shortlist can be ordered.
- Rarity converts to a replacement cost: the expected number of domain runs
  to farm a better piece. An on-set EM goblet alone is about 1 in 400 drops.
- Rarity is not value. A rare piece for an unwanted role is still unused; the
  account checks below cover that.

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
   calibrated cells.
3. Stat-profile groups and Keep / Level verdicts in the overlay.
4. Whole-bag OCR scan of all five-star levels, then the fodder list.
5. Reviewed weights for all characters; damage-derived weights for close calls.

Open questions: default rarity cutoffs and the leveling bar per checkpoint;
whether the inventory card's equipped-by line can be read reliably; how to
model reshaped and Transmuter pieces, which the ordinary model excludes.
