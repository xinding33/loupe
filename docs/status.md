# Artifact Lens: project status

Date: 2026-10-13
Status: offline build, lint, and tests pass. Live verification, performance
measurement, and broader calibration are still open.

This page is the current snapshot. [Next features](next-features-plan.md) holds
the detailed work order and acceptance criteria; the README describes shipped
behavior. Update this page when a listed item changes.

## Verified on 2026-10-13

Checked at commit `f64b9fd` with Xcode 27.0 (Swift 6.4) on macOS 27.0.1:

- `make check` passed. Strict `swift-format` lint reported nothing.
- 94 ArtifactCore tests and 61 ArtifactLens tests passed.
- Two recorded-sequence tests were skipped. They need private PNG fixtures
  through `ARTIFACT_LENS_FIXTURES`, which are not in the repository.
- `make app` built `dist/Artifact Lens.app` and its ad-hoc signature passed
  strict verification. The app was not launched.
- The source fingerprint is
  `sha256-96cfbabf05f58cc0f671a22fc9edfbb2e890e187f71dff3f65a46c412818332b`,
  identical to the 2026-09-27 integration build. `Sources`, `Package.swift`,
  `Resources/Info.plist`, and `Makefile` have not changed since then.

These are offline checks. They do not establish live OCR reliability, overlay
behavior on the real game, or performance.

## Repository

- One commit on `main`: the 2026-10-10 import of the working tree. Earlier
  history was not carried over.
- Remote: private GitHub repository `xinding33/artifact-lens`. No pull requests,
  issues, or CI.
- 36 Swift source files in two targets, 20 test files, no external packages.
- Inventory and diagnostics live outside the repository under
  `~/Library/Application Support/ArtifactLens/`. A new Mac starts with no saved
  inventory; move it with the app's export and import.

## Implemented

- Selected-window capture, on-device Vision OCR, and two-frame verification for
  Inventory cards and the Enhance stat panel.
- Compact overlay with monitor placement, drag and reset, click-through result
  surface, and configurable expand and disable shortcuts.
- Exact +20 outcome distribution for ordinary five-star upgrades: current,
  median, P90, and best possible, with saved-inventory rank comparisons.
- Saved inventory with collection, upgrade linking, GOOD and backup import,
  undo, and coverage by slot and main stat.
- Character assessment for 15 reviewed roles, dataset `reviewed-2026-09-27.1`,
  with a five-candidate shortlist shared by the dashboard and overlay.
- Experimental S/A/B/C/D tiers for 15 role/slot/main combinations, calibration
  `experimental-reviewed-2026-09-27.1`: Furina 7, Itto 6, Kuki Shinobu 2.
- Opt-in diagnostic buffer, report preview and export, and a headless
  [replay command](diagnostic-replay.md).
- Manual profiles and pasted card text for cases outside reviewed coverage.
- Auto-press, ported from Mash on 2026-10-22: repeats one key while the chosen
  app is in front, with a toggle shortcut, banner and auto-off timer. Needs
  Accessibility. Settings and timer logic are covered by ArtifactCore tests;
  key posting and the toggle have not been checked live.

## Live checks so far

The user ran basic checks on 2026-09-27 against the preceding build:
game-monitor placement, expanded readability, both physical shortcuts, +0
Inventory and Enhance readings, a +20 Inventory reading, and disable followed
by re-enable. Nothing has been checked live since.

## Open work

In suggested order. The first two need the game running.

1. Live verification, [plan section 6](next-features-plan.md): continuous OCR
   stability, click-through and game focus, moving the game between monitors
   including fullscreen and mixed display scales, shortcut conflicts, report
   preview and save, and disabling or changing sessions during a preview.
2. Performance: CPU, memory, OCR count, and OCR latency with the reader
   disabled, enabled, and enabled with buffering. Buffering stays off at launch
   and sampling stays at two reads per second until this is measured.
3. Recorded fixtures: no recorded Enhance sequence is available to the two
   skipped tests, so live-reader regressions are covered only by synthetic
   images.
4. Tiers: all 15 reviewed roles are graded by rarity among new drops, with
   cutoffs fitted to the earlier hand calibration. Keep / Level verdicts and
   shortlist ordering by rarity are next. See
   [grading approach](grading-approach.md).
5. Character coverage: 15 roles, one per character. This is not a roster-wide
   search and the app says so.

Grading direction changed on 2026-10-22: see [grading approach](grading-approach.md).
Its first step, enumerating final substat outcomes once for every profile, is
implemented as `RollOutcomes`. Its second step replaces the hand-calibrated
tier cells with tiers from rarity among new drops (`DropRarity`), so every
reviewed role is graded.

Deferred by decision: crafted and Dust probability models, full-build damage
optimization, automatic character ownership syncing, cloud reports, and
adaptive OCR scheduling. No automatic upgrade, salvage, or discard actions.

## Reading the other documents

Current reference:

- [Grading approach](grading-approach.md): agreed 2026-10-22 direction for
  Keep / Level / Fodder verdicts across all characters, and its work order.
  It supersedes the earlier no-verdict stance.
- [Coverage and source limits](character-coverage-expansion.md)
- [Shortlist behavior](character-shortlist.md)
- [Original calibration](character-pilot.md) and
  [expanded calibration](tier-expansion-review.md)
- [Starter model evidence](starter-probabilities.md)
- [Diagnostic report format](diagnostics-design.md) and
  [replay command](diagnostic-replay.md)

Historical, kept for the reasoning behind decisions:

- [Overlay redesign plan](overlay-redesign-plan.md) and
  [evaluation proposal](evaluation-design.md). Both describe proposals; some
  parts were changed during implementation. The unknown-fourth-stat branch in
  the next-features plan was replaced because current cards preview that stat.
- `docs/tasks/*.md` are the briefs given to the implementation threads. Their
  checkout paths and thread identifiers refer to a workspace that no longer
  exists. Do not follow their setup instructions.

## Known gaps in tooling

- No CI. The synthetic Vision tests need macOS Vision services and normal
  execution outside a restricted process sandbox.
- `make app` signs with this Mac's Developer ID when it has one, otherwise ad
  hoc. There is no notarized distribution.
- Live capture and window tracking require macOS 15.2 or later. The package
  still targets macOS 14 for manual entry.
