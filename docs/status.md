# Loupe: project status

Date: 2026-10-13
Status: offline build, lint, and tests pass. Live verification, memory and
in-game performance measurement, and broader calibration are still open.

This page is the current snapshot. [Next features](next-features-plan.md) holds
the detailed work order and acceptance criteria; the README describes shipped
behavior. Update this page when a listed item changes.

## Verified on 2026-10-13

Checked at commit `f64b9fd` with Xcode 27.0 (Swift 6.4) on macOS 27.0.1:

- `make check` passed. Strict `swift-format` lint reported nothing.
- 94 LoupeCore tests and 61 Loupe tests passed.
- Two recorded-sequence tests were skipped. They need private PNG fixtures
  through `LOUPE_FIXTURES`, which are not in the repository.
- `make app` built `dist/Loupe.app` and its ad-hoc signature passed
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
- Remote: `xinding33/loupe`, renamed from `artifact-lens` and made public for
  the first release in October 2026. CI runs lint, tests and an ad hoc bundle
  build on every pull request.
- 36 Swift source files in two targets, 20 test files, no external packages.
- Inventory and diagnostics live outside the repository under
  `~/Library/Application Support/Loupe/`. A new Mac starts with no saved
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
- Character assessment for every playable character through 12 shared
  [archetypes](archetypes.md), dataset `archetypes-2026-10-26.1` (2026-10-26),
  plus the 15 reviewed roles of `reviewed-2026-10-26.1`, which keep their
  advice; the 2026-10-26 versions add four-star alternative sets. A five-candidate shortlist is shared by the dashboard and overlay.
- Experimental S/A/B/C/D roll grades for every role, calibration
  `roll-2026-10-26.1`: example starts from the user's rules of thumb, a
  rarity limit, and weighted rolls (crit over the scaling stat).
- Opt-in diagnostic buffer, report preview and export, and a headless
  [replay command](diagnostic-replay.md).
- Four-star pieces (2026-10-26): read, saved and imported with their rarity, judged by set and
  main stat for characters whose builds list Instructor or The Exile. Star counting on a
  four-star card has not been checked live.
- Manual profiles and pasted card text for cases outside reviewed coverage.
- Auto-press, ported from Mash on 2026-10-22: repeats one key while the chosen
  app is in front, with a toggle shortcut, banner and auto-off timer. Needs
  Accessibility. Settings and timer logic are covered by LoupeCore tests;
  key posting and the toggle have not been checked live.

## Performance, measured 2026-11-23

A release-build benchmark on a 240-frame recording (mostly Inventory cards and
card-less screens) and a real 145-piece inventory, run outside the game:

- Reading a frame took 142 ms (88 ms CPU): every frame ran the Enhance pass
  (two Vision requests, about 76 ms) before the full-window Inventory read
  (about 64 ms). After an Inventory card, the next frame now tries the
  Inventory read first and skips the Enhance pass when it finds a card:
  78 ms (63 ms CPU) per card frame. Card-less frames still run both, about
  140 ms. Readings on all 240 frames are unchanged.
- The model republished about five times a second with nothing new, and each
  republish re-rendered the dashboard and overlay for about 21 ms of main-thread
  CPU, 16 ms of it rebuilding the character shortlist 28 times. A repeated
  verified card, a quiet freshness tick and an unchanged overlay status now
  publish nothing, and the shortlist is built once per change.
- Grading a new +0 four-line piece took about 97 ms, 66 ms of it scoring the 15
  preset profiles that only manual-profile mode shows. One roll enumeration is
  now shared, and the presets are scored only in that mode: about 21 ms.
- Auto-press ran on the main queue, so main-thread stalls delayed presses: at
  12 a second the median gap was 84 ms, but 10% of gaps were 139 ms or more and
  one was 435 ms. Presses now run on their own high-priority queue. A test holds
  the cadence through a 300 ms main-thread stall; it has not been re-measured
  in the game.

- Sampling changed on 2026-11-23, approved by the user: capture delivers five
  frames a second. A new frame is read at once while the reading is changing,
  otherwise half a second after the last read, so a settled screen is still
  read twice a second. Simulated, a new card is verified 0.54 s after it
  appears, against 0.83 s before. A reading that never settles gets four fast
  reads and then the usual two a second.
- A frame the stream reports as a repeat of one already read takes that read's
  outcome without Vision, and is read again every two seconds; Enhance fields
  go through confirmation again. Driven through the new pipeline at their
  0.5 s spacing, all 240 recorded frames gave the same outcome as reading every
  frame.
- Tried and dropped: reusing a read when a new frame's pixels nearly match the
  frame last read. In Inventory the selected item's highlight pulses, so only 9
  of 240 frames matched, and a review showed that frames within any workable
  threshold can still read differently (one digit changing in a small window).
  Nothing short of the stream's own "unchanged" is reused.

Memory, and CPU with the reader disabled or buffering on, are not measured. Nor
are the cost of capturing five frames a second and how often real frames arrive
idle.

## Live checks so far

The user ran basic checks on 2026-09-27 against the preceding build:
game-monitor placement, expanded readability, both physical shortcuts, +0
Inventory and Enhance readings, a +20 Inventory reading, and disable followed
by re-enable.

On 2026-10-25 the user clicked through Inventory and Enhance in v0.1.0 while
348 frames of the GeForce NOW window were recorded and replayed offline. The
frames stay on that Mac; they show the account UID. Findings, all fixed:

- 46% of Inventory frames were rejected as low confidence because Vision read
  the rarity stars as junk text at 0.30, even on an unchanged card. Confidence
  now comes only from the lines the parser reads.
- Vision returned the HP main stat as "HР" with a Cyrillic Р on four cards.
  Cyrillic and Greek look-alikes now map to Latin in both readers.
- Enhance split the "Elemental Mastery" main-stat label over two lines and
  rejected the panel; the halves are now joined. A short "HP" label at 0.50
  confidence no longer blocks changed stats, since labels are already checked
  against stat names and the verified card.

After the fixes, 313 of 314 Inventory card frames parse (the other is
mid-transition) and all four Enhance frames read.

A second recording and a user video the same day added the character
Artifacts screen, where the card is narrower, the main stat shares a row with
its value, and the set line ends in an equipped count ("Set: (4)"). Fixes:
"(unactivated)" on its own line, Vision splitting one row into two
observations, punctuation inside labels, stray marks at line ends, a missed
level tag (read again from an enlarged crop), and a lost flower or plume
main-stat label. Afterwards 155 of 162 card frames in the recording, 52 of 53
in the video and 313 of 314 in the first recording parse, with no wrong
readings among them. The failures are single frames that two-frame
verification skips. Enhance read 3 of 4 video frames; Enhance upgrades past
+0 are still unrecorded.

## Open work

In suggested order. The first two need the game running.

1. Live verification, [plan section 6](next-features-plan.md): continuous OCR
   stability, click-through and game focus, moving the game between monitors
   including fullscreen and mixed display scales, shortcut conflicts, report
   preview and save, and disabling or changing sessions during a preview.
2. Performance: memory, and CPU with the reader disabled and with buffering,
   measured in the game. Reading and grading costs are above. Buffering stays
   off at launch.
3. Recorded fixtures: no recorded Enhance sequence is available to the two
   skipped tests, so live-reader regressions are covered only by synthetic
   images.
4. Grading: every role has a roll grade, and verdicts follow it. Next: a
   whole-bag scan, and an ownership filter so verdicts count only the user's
   characters; without one, Keep stays high on flowers. Verdict defaults still
   need tuning on a real inventory. See [grading approach](grading-approach.md).
5. Character coverage: every character has archetype roles; 15 were reviewed
   one by one. Archetype assignments for characters from 5.0 onward rest on
   one or two guides each, and "Somnia" and the Cryo Traveler are unassigned.
   See [archetypes](archetypes.md).

Grading direction changed on 2026-10-22: see [grading approach](grading-approach.md).
Its first step, enumerating final substat outcomes once for every profile, is
implemented as `RollOutcomes`. Its second step replaces the hand-calibrated
tier cells with tiers from rarity among new drops (`DropRarity`), so every
reviewed role is graded. Its third step adds Keep / Level / Review / Fodder
verdicts (`VerdictEngine`) to the overlay and dashboard. On 2026-10-26 the
letters became roll grades (`RollGrade`) with weighted rolls, and verdicts
follow them.

Deferred by decision: crafted and Dust probability models, full-build damage
optimization, automatic character ownership syncing, and cloud reports. No
automatic upgrade, salvage, or discard actions. Adaptive OCR scheduling, also
deferred until then, was approved on 2026-11-23; see Performance.

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

- The synthetic Vision tests need macOS Vision services and normal execution
  outside a restricted process sandbox.
- `make app` signs with this Mac's Developer ID when it has one, otherwise ad
  hoc. Tagged releases are signed, notarized and published by
  `.github/workflows/release.yml`.
- Live capture and window tracking require macOS 15.2 or later. The package
  still targets macOS 14 for manual entry.
