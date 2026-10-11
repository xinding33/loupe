# Starter probabilities and score meaning

Reviewed: 2026-09-26. Scope: ordinary five-star artifacts.

## Current-game decision

Keep requiring the fourth stat. Do not add an unknown-fourth mixture or a manual
inference switch for the current game.

HoYoverse's official account announced on 2025-09-05 that, after Version Luna I,
five-star artifacts with three initial minor affixes show a preview of the
fourth affix. That affix activates at +4. This applies to five-star artifacts,
not just the two sets introduced in that announcement.
[Official Luna I artifact overview](https://www.reddit.com/r/Genshin_Impact/comments/1n9134u/).

The supported interpretation is therefore a known but unactivated fourth stat.
This research found no supported current-game exception with a genuinely
unrevealed fourth stat. A missing OCR line, cropped card, or incomplete import
does not establish such an exception. Historical three-line records remain
incomplete inputs; read the current card or enter its previewed stat and value.
No live game or private inventory was inspected for this decision.

## What the probability evidence establishes

The original KQM study, "Uneven Substats Distribution" (2021-04-20, version 1.4),
reports unequal initial-stat frequencies and explains why a pooled frequency
table cannot be used directly for a fourth-stat draw: the main stat and existing
substats exclude outcomes. Its datamined source link is no longer available,
and the study explicitly qualifies its fitted weights. This is evidence for
weighted, conditional selection, not verified present-day exception behavior.
[KQM research and methodology](https://library.keqingmains.com/evidence/equipment/artifacts#uneven-substats-distribution).

Neither that study nor the official preview announcement supplies a verified
current-game probability table for a genuinely unrevealed fourth stat and its
initial roll tier. No new numerical selection weights are shipped. The existing
ordinary-upgrade model still assigns 1/16 to each of four known stats crossed
with four roll tiers. This pass tests that model's arithmetic; it does not claim
new empirical verification of the server's random-number generator.

If a supported exception is documented later, verify its acquisition rules and
both probability tables before implementation. An inference API must then use
a typed, explicit manual opt-in, default to requiring the known fourth stat,
exclude the main and existing stats, normalize the legal branches, and consume
the +4 activation event before ordinary increments. Missing OCR must never
select that opt-in automatically.

## Preserved API and math

`Potential.evaluate(_:profile:inventory:scope:excluding:)` is unchanged.
Three active stats without `Artifact.unactivated` still throw `ArtifactError`.
The error asks for the stat shown as unactivated and explains its +4 activation.
Known unactivated stats require both a legal stat and one legal initial roll.
Crafted guaranteed-roll and Dust/reshaped artifacts remain outside ordinary odds
through `RollRule.special`.

For a known three-stat starter at +0 through +3:

- Current score includes only active substats.
- Final-score outcomes include the known fourth stat's fixed initial value.
- +4 activates that stat; four random upgrades remain at +8, +12, +16, and +20.
- The final distribution equals the distribution immediately after activation
  at +4, before any other substat changes.

A four-active-stat starter at +0 through +3 retains five random upgrades.
At +20 the distribution is a single final score. `Artifact.nextCheckpoint`
already returns the next multiple of four, or `nil` at +20.

Quantiles, strict improvement, tie-inclusive ranks, duplicate saved pieces,
candidate exclusion, comparison scope, and empty comparison pools retain their
existing behavior. A rank-three probability exists only with at least three
saved comparables. The distribution is exact enumeration of the existing
normalized-score model, not a character damage calculation.

## Score labels and UI handoff

`Profile.explanation` now labels presets as `Valued stats: CRIT Rate + CRIT DMG`
and custom definitions as `Roll weights: CRIT Rate 100/100, CRIT DMG 50/100`.
A profile must match both a preset's name and weights to receive preset wording.
Zero-weight stats are omitted; an empty custom definition says `Roll weights: none`
and remains invalid for potential evaluation.

A maximum-sized roll at weight 100 contributes one score point. Weight 50 gives
that roll half a point. Smaller rolls contribute their normalized fraction.
CRIT Rate and CRIT DMG use their own maximum roll amounts, so equal roll weights
already account for their approximately 1:2 amounts. Do not double CRIT Rate's
weight or present these weights as character percentages or damage multipliers.

The parent owns UI integration:

- Show the profile name beside the current or projected score.
- Keep current score, median +20, P90 +20, and best possible distinct.
- Explain P90 as a high-end outcome threshold, not a guarantee or player rank.
- Show only the final score at +20, without redundant upgrade projections.
- Ask for the previewed fourth stat when a three-line card is incomplete.
- Use `Artifact.nextCheckpoint` for the next upgrade level. A known unactivated
  stat has a fixed +4 activation; it is not a random favorable-stat draw.
- Use the same profile and comparison scope for role grades and account odds.
  Tier integration and favorable-roll presentation are outside this change.

## Regression coverage

`StarterPotentialTests` covers preset/custom labels, all four normalized CR/CD
tiers, custom weighting, +0/+3 activation conditioning, probability mass and
endpoint probabilities, four-active-stat event counts, missing-fourth and
special-rule rejection, and a +20 three-stat-origin point mass with duplicate
and tie handling. Existing core regressions remain unchanged. Weighted unknown
mixture tests are intentionally absent because no such model is shipped.
