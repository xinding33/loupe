# Artifact Lens: next features

Date: 2026-09-27
Status: character expansion and broader calibration passed offline integration.
The preceding build passed the basic live checks listed below.

## Implementation update

- Character coverage now includes 15 reviewed roles. The dashboard and overlay
  share a five-candidate shortlist, preserve manual selection, and provide access
  to all eligible candidates. See [coverage](character-coverage-expansion.md) and
  [shortlist behavior](character-shortlist.md).
- Basic live checks on 2026-09-27: the user confirmed game-monitor placement,
  expanded readability, and both physical shortcuts. The +0 Inventory/Enhance
  and +20 Inventory readings matched the inspected cards. Disable cleared live
  results while preserving nine saved records; re-enable required fresh Inventory
  context. These checks do not establish continuous OCR stability, click-through,
  monitor-move behavior, report saving, or measured performance.
- Score labels, reviewed character matching, selected-role forecasts, saved top-three
  comparisons, and inventory coverage summaries are integrated.
- Experimental grades cover 15 explicit role/slot/main combinations for Furina,
  Itto, and Kuki. The original four rules are unchanged; the other ten reviewed
  characters remain ungraded. See [expanded calibration](tier-expansion-review.md).
- The [replay command](diagnostic-replay.md) runs without the desktop app and
  packaged builds carry a source fingerprint.
- Research replaced the proposed unknown-fourth-stat extension: current cards
  preview the fourth stat. Missing input must be read, not inferred. See
  [starter evidence](starter-probabilities.md).
- UI redesign (2026-09-26): shared tier badges, Median/P90/Best ladder, and a
  saved-account block that always shows scope and count; grouped dashboard
  sidebar; icon control strip with Report; restyled report preview. Synthetic
  renders and the limited live checks above cover this interface.
- Whole-roster coverage, further calibration, monitor-move/report checks,
  and live performance measurement remain pending. Buffering stays off
  at launch and enabled sampling remains two reads per second.

The work order below records the original proposal, including the now-replaced
unknown-fourth-stat branch. No automatic upgrade or discard actions were added.

Offline integration on 2026-09-27: `make check` passed strict formatting and
reported 61 ArtifactLens tests and 94 ArtifactCore tests. The two optional
private recording tests were skipped. Synthetic Vision tests needed normal
execution outside the process sandbox; they passed without private fixtures.
New calibration dispatch tests failed before implementation and passed after it.
Synthetic shortlist renders show five of 15 eligible users with manual selection
preserved. Rendering does not verify live interaction or OCR performance.

`make build` passed. The executable was packaged separately as
`dist/Artifact Lens 2026-09-27.app` to leave the running app's bundle untouched.
The new bundle passed strict signature verification and headless replay help;
its source fingerprint is
`sha256-96cfbabf05f58cc0f671a22fc9edfbb2e890e187f71dff3f65a46c412818332b`.
It was not launched. The default `make app` target still writes
`dist/Artifact Lens.app` on future builds.

Prioritize understandable evaluation, character matches, and tiers. Verify the
existing overlay and report flow on the live game in parallel. Keep the current
two samples per second while enabled until measurements justify changing it.

## Starting point before this iteration

Implemented and covered by automated tests:

- Compact overlay, selected-window monitor placement, expansion and disable shortcuts.
- Capture shutdown and stale-result rejection when disabled.
- Median, P90, and best-possible +20 scores with saved-inventory comparisons.
- Opt-in local diagnostic buffer, preview, report export, and replay APIs.

Recorded Enhance regressions passed with diagnostics off, on, and replayed.
Native multi-monitor behavior, report saving, and live performance still need
verification. Character matching and S/A/B/C/D grading were not yet implemented.

The [original plan](overlay-redesign-plan.md) records agreed behavior and completed
work. The [evaluation proposal](evaluation-design.md) contains source evidence,
calibration examples, and ranking semantics. The
[diagnostics design](diagnostics-design.md) describes the implemented report flow.

## 1. Clarify the existing scores

Replace preset descriptions such as "CRIT Rate 100%, CRIT DMG 100%" with
"Valued stats: CRIT Rate + CRIT DMG". Label custom settings as roll weights.
Explain the score in expanded details: one maximum-sized useful substat roll
is one point. Equal Crit roll weights already account for the approximately
1:2 CRIT Rate to CRIT DMG stat amounts. Do not double CRIT Rate's weight.

Name the profile beside its score. Separate the current score from projected
+20 results. Explain P90 as a high-end outcome threshold, not a guaranteed
result or a ranking among players. Label the maximum "Best possible".

Acceptance:

- Equivalent normalized CRIT Rate and CRIT DMG rolls retain equal scores.
- Preset labels no longer resemble character stats or damage multipliers.
- Current, median, P90, and best possible remain distinct at low levels.
- At +20, show the final score without redundant upgrade projections.

## 2. Add realistic character matching

Build a small, versioned local role dataset using the existing sourced proposal.
Start with Furina, Itto, Xiangling, Kuki Shinobu, and Kokomi as a validation pilot.
This tests HP, DEF, ATK, EM, ER, and healing uses; it is not roster-wide coverage.

Each role needs legal main stats, preferred and alternative sets, useful
substats, build conditions, and source/review dates. Guide priorities must not
silently become damage coefficients. Confirm permitted source-data reuse before
bulk collection or distribution; do not build a guide scraper in this phase.

Match slot and main stat first. Then explain useful substats and set fit.
Include unowned characters and credible off-pieces. Distinguish an on-set
candidate from an active set bonus, which requires other equipped pieces.
Unknown team, weapon, constellation, or ER conditions must remain visible.

Return up to five distinct characters, with one leading role per character.
Do not pad the list. Before tier calibration, call these "Potential users"
without claiming a strongest-to-weakest order. After calibration, rank by
role-specific quality, conditions, and set fit rather than raw cross-role scores.

Acceptance:

- A strong off-piece remains eligible despite its set.
- Standard Kokomi healing does not gain quality from Crit-heavy substats.
- EM-focused pieces can match without Crit; reaction conditions remain explicit.
- Multiple variants do not fill the list with the same character.
- Missing coverage says "No reviewed match", never "Nobody can use this".

Expand the reviewed dataset after the pilot passes. Show coverage in the app;
only describe results as roster-wide once that coverage is actually reviewed.

## 3. Calibrate and implement S/A/B/C/D tiers

Use role-, slot-, and main-stat-specific calibration. Start with transparent
useful-roll scoring, then test whether it distinguishes the reviewed examples.
Keep secondary utility visible instead of assigning unsupported numeric weights.
Prepare a concrete boundary table with representative artifacts for one review
before encoding the grade thresholds.

Proposed meanings:

- S: exceptional for the stated use.
- A: strong with a clear use.
- B: useful but replaceable.
- C: marginal or narrow.
- D: poor for that reviewed use.

Missing calibration is "Ungraded". A correct EM main stat must not receive D
merely because an EM substat is impossible on that piece. ER requirements and
Crit caps depend on the full build; show conditional assessments rather than
claiming exact cap-aware damage value.

For unfinished pieces, emphasize the median projected +20 grade and show the
best-possible grade separately. At +20, show the actual grade. Every grade must
name its supporting role. Use the same role for median, P90, and best possible;
do not select a different winning role for each outcome.

Acceptance:

- Review examples around every shipped tier boundary, including non-Crit roles.
- Adding a useful roll cannot lower the grade under unchanged assumptions.
- Inventory strength does not change intrinsic quality.
- Unresolved conditions and unsupported scoring remain visible.
- A rare S ceiling cannot appear as an already-earned S grade.

## 4. Complete starter probabilities and upgrade decisions

The current model requires four known substats, including a known unactivated
fourth stat. Support genuinely unknown fourth stats as a separate ordinary-roll
case after verifying the eligible-stat selection and roll-tier probabilities.
Exclude existing substats and the main stat when enumerating eligible outcomes.
Branch on the fourth stat, consume its reveal event, and combine subsequent
upgrade distributions using the verified probabilities.

Do not interpret an OCR-missed fourth line as an unknown in-game stat. Preserve
the existing known-unactivated path and crafted/reshaped exclusions.

Connect each reviewed role to its own outcome distribution and inventory pool.
Show the chance to beat the best saved piece and reach the saved top three.
Keep strict improvement separate from tie-inclusive rank. Show "Not enough
comparables" where a benchmark is absent, rather than inventing a percentage.

For the next upgrade checkpoint, explain which rolls help and whether even the
ceiling can improve the relevant benchmark. Include the chance of reaching A
or better once calibrated. Let the user decide whether a long shot is worth
trying; do not introduce an arbitrary XP/Mora cutoff or automatic discard rule.

Acceptance:

- Starter distributions sum to one and contain only legal fourth-stat outcomes.
- Known fourth-stat results remain unchanged; revealing it conditions the forecast correctly.
- Verify four-stat starters, +4 reveal, intermediate levels, and +20 point masses.
- Ties, duplicate saved pieces, and candidate exclusion retain their documented behavior.
- Account probabilities use the same role and assumptions as the displayed grade.

## 5. Connect the results to a small overlay and useful inventory coverage

Keep the collapsed panel small. Proposed content:

- Artifact identity and read status.
- Median +20 grade, or final grade at +20, with the leading character/role.
- One account comparison: chance to beat the best saved comparable piece.

Expanded content should show up to five character matches with reasons, set or
off-piece status, median/P90/best-possible outcomes, and saved top-three chances.
Always show comparison scope and sample count. Do not add the rejected P25-P75
range or imply that saved-account ranks are Akasha population percentiles.

Build guided scan progress on the existing collection/import path. Summarize
saved +20 coverage by slot and main stat, and identify sparse comparison groups.
Call it "Saved inventory" until completeness is established. Keep collection
explicit and preserve upgrade identity and legitimate duplicate artifacts.

Acceptance:

- The collapsed panel fits without truncating the grade's role or projection label.
- Expanded content handles five matches, conditional notes, and no-match cases.
- No inventory still permits intrinsic quality and potential assessment.
- Sparse inventory cannot produce a misleading universal "best on account" claim.

## 6. Verify live behavior and finish agent-facing diagnostics

Run these checks against the existing implementation before calling the desktop
experience verified:

- Move the game between monitors, including fullscreen and mixed display scales.
- Test shortcut holds/conflicts, expansion, drag/reset, click-through, and game focus.
- Disable and resume sharing; confirm no new capture/OCR work starts while disabled.
- Open a report, inspect all retained evidence, cancel, save, and reveal the result.
- Change sessions or disable during preview; verify unsaved evidence is released.

Measure enabled diagnostics off, enabled diagnostics on, and disabled states
under the same game conditions. Record CPU, memory, allocation rate, OCR count,
and OCR latency. Keep buffering off at launch until measured overhead is acceptable.
Fix observed lifecycle or recognition defects before considering adaptive sampling.

Add a documented report-replay command around the existing replay API so an
agent can reproduce a saved issue without the live game. Include an identifiable
app build and evaluation/data versions in reports. Clearly report missing
verified Inventory context and partial Inventory replay; never substitute saved
text for OCR. Add a context checkpoint only if a real report demonstrates that
the missing initial context prevents reproduction.

Acceptance: a saved local report can be replayed with documented inputs, producing
the actual parser result and a comparison with the user's annotated expectation.
No report uploads, extra automatic recording, or inventory corrections occur.

## Execution order and boundaries

First deliver score clarity and the five-character matching pilot. Calibrate
tiers next, then connect graded outcomes and account comparisons to the overlay.
Unknown-fourth-stat modeling can run alongside role-data work. Live verification
can proceed independently and should not block offline evaluation development.

If implementation is delegated later, use separate ownership for evaluation
math, role data/calibration, and live verification. One integrator owns shared
Model and Views changes. Agree on the result types before parallel edits.
The approved implementation used separate probability, character, and replay
threads. Shared Model and Views integration remained with the parent thread.

Defer full-build damage optimization, automatic character ownership syncing,
crafted/Dust probability models, cloud reports, and adaptive OCR scheduling.
Preserve manual profiles for uses outside reviewed character coverage.
