# Character browsing shortlist

Reviewed 2026-09-27. This UI policy selects potential users for browsing. It
does not identify optimal builds or rank damage across characters. The role
dataset and experimental calibration retain their own versions and limits.

## Ordering and selection

`CharacterShortlist` accepts the current artifact, engine matches, and an
optional manually selected character ID. It orders eligible matches by:

1. Active core substats or a core-useful variable main before neither.
2. Preferred set, alternative set, then off-piece.
3. Core-useful variable main before other main-stat eligibility.
4. Stable character ID, then role ID.

A core-useful variable main belongs to the role's `usefulStats` and occupies
sands, goblet, or circlet. Fixed flower/plume mains do not earn this priority.
An EM-only role with an EM main therefore remains a useful main-stat fit even
though an EM substat is impossible. Among equal set fits, it is not buried
behind alphabetically earlier Crit users with only substat fit. This is a
browsing convention, not a numerical estimate of main-stat value. Eligible
damage-bonus, healing, or ER mains outside the role's core-stat list do not
receive this additional priority.

Only activated substats count as active core presence. A known unactivated
line remains forecast information. Neither roll amounts nor the number of
useful lines affect ordering. Set fit does not prove set-bonus activation;
off-pieces remain accessible even when on-set candidates precede them.

The first ordered match is the default headline. A manual choice overrides
that default while it is eligible. At most five distinct characters appear
in the shortlist. A manual choice outside the first five replaces the fifth
entry without changing the relative order of the displayed entries. The full
list keeps its browsing order and contains each character once. The engine
currently supplies one reviewed role per character; this UI does not evaluate
or compare alternative roles.

The overlay and dashboard use the same `visibleMatches`. The dashboard starts
with the shortlist and offers "Show all N eligible users" to reveal the full
list. Selecting there updates the headline and overlay; collapsing the list
still retains that selection. Counts come from eligible distinct matches,
not a hardcoded roster size. Both surfaces label partial coverage and identify
the list as potential users, not damage ranking.

## API and invariants

- `allMatches`: all distinct engine matches in browsing order.
- `visibleMatches`: up to five entries, including the selected eligible user.
- `selectedMatch`: the eligible manual choice, otherwise the first entry.
- `Model.characterShortlist`: derives this value from existing evaluation state.
- `Model.selectedMatch`: delegates to that value for the headline and fixed-role
  forecast, account comparison, and diagnostic selection.

No artifact or no matches yields an empty shortlist and no selected match.
A stale manual ID falls back to the current default without fabricating a
match. No shortlist is cached, so the existing pending-evaluation, cancellation,
disable, and stale-result guards also clear the derived list.

Raw scores, experimental grades, ownership, and saved inventory do not affect
ordering. Missing calibration stays ungraded, never D. Kuki does not gain
priority merely because her flower/plume cells have grades. The no-eligible-core
suppression remains intact: an EM-only role on an EM main still has no scalar
comparison. Manual profiles, ordinary roll math, grade thresholds, actual +20
results, and median/ceiling forecast semantics are unchanged.

## Evidence and limits

No additional guide was fetched, copied, or converted into role data for this
UI change. Its inputs remain the reviewed local role records described in
[character-pilot.md](character-pilot.md) and the
[evaluation design](evaluation-design.md). This document grants no source-reuse
or distribution permission. Source review and expanded role facts belong to
the role dataset, not the browsing policy.

Synthetic tests cover selection beyond five, duplicate identities, input-order
independence, score and grade independence, main-only EM fit, fixed mains,
unactivated stats, manual profiles, and pending/stale clearing. Optional
`ARTIFACT_LENS_UI_PROOF` renders use synthetic data only. No live game, private
inventory, recording, diagnostic report, or packaged app is required.
