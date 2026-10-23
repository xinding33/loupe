# Loupe overlay redesign

Date: 2026-09-26

For the next work order after the initial implementation, see
[Next features](next-features-plan.md). The sections below retain the original
design and implementation handoffs.

This is an implementation plan, not a description of shipped behavior. The
parent T3 thread coordinates integration and live verification:
`local:56c69391-8837-4946-9407-76dacdcd050c`.

## User goals and scope

Help the user decide which artifacts to try and when to continue upgrading.
Evaluate realistic uses across all characters, whether owned or unowned. Keep
strong off-pieces visible. Artifact XP and Mora are secondary concerns.

Continue supporting five-star English cards and ordinary upgrades. Crafted
guaranteed rolls and Dust reshaping remain outside the probability model.
Never automate upgrading, spending, salvage, or inventory deletion.

Separate three assessments:

- Character suitability: who can realistically use the set, main stat, and substats?
- Artifact quality and potential: how strong is it for a stated role, now and at +20?
- Account value: how does it compare with saved comparable pieces?

Do not equate a useful-roll score with damage, a population percentile, or an
Akasha leaderboard rank. Missing guide coverage does not imply a bad artifact.

## Agreed overlay behavior

### Placement and interaction

- Anchor to the shared GeForce NOW window's monitor, near the top-right corner.
- Remember a user-adjusted offset and keep the panel within the display bounds.
- Reposition after window moves, display changes, and fullscreen transitions.
- If the game spans displays, use the display containing the largest window area.
- Offer a manual placement recovery control; do not guess from the mouse position.
- Default to compact mode. Expand explicitly, without stealing game focus.
- Keep the noninteractive overlay surface click-through. Provide an interactive
  handle and accessible main-window/menu controls for expansion and reporting.

Default, configurable shortcuts:

| Shortcut | Action |
| --- | --- |
| Option + backtick | Expand or collapse |
| Option + Shift + backtick | Enable or disable Loupe |

Shortcut registration failure or a conflict must be visible. Expansion must not
silently resume disabled capture. Avoid repeating a toggle while a key is held.

### Enabled and disabled states

Collapsed and expanded both mean the reader is enabled. Disabled means:

- Hide the overlay and stop the capture stream and OCR scheduling.
- Invalidate late results and cancel pending evaluation work.
- Stop diagnostic recording and release buffered images.
- Preserve inventory, settings, and the shortcut listener.

An already-running OCR operation may need to finish, but its result must not
update the UI or inventory after disable. No new OCR may be scheduled.

On enable, reuse the selected window only if macOS still permits capture.
Otherwise request sharing again. Show a waiting state until a fresh card is
verified. Never revive stale advice. Enhance requires verified Inventory
context; if that context is lost on disable, explain that Inventory must be
read again rather than weakening validation.

Keep the current two-samples-per-second configuration while enabled initially.
Measure before changing it. Adaptive OCR, pixel-change detection, and slower
confirmation are deferred. Animated Enhance backgrounds previously caused
reader instability; a new optimization must pass recorded-sequence regressions.

## What to display

### Compact panel

Start around 280 by 100 points, subject to native layout testing. Show:

- Slot, main stat, level, and a small reading-status indicator.
- A short upgrade assessment with its primary reason.
- The median projected +20 tier for unfinished pieces, clearly labeled.
- The leading realistic character matches.
- Chance to strictly beat the best saved comparable piece, when available.

Do not squeeze missing data into fake scores or zero probabilities. Keep the
compact view small even if some information must move to the expanded view.

### Expanded panel

- Up to five distinct character matches, fewer if fewer are credible.
- Character role, set fit, main-stat fit, useful substats, and material conditions.
- On-set and off-piece matches distinguished visibly.
- Standard builds first; niche, weapon-specific, and constellation-dependent
  variants available under more matches with their conditions.
- Current quality and final-outcome summaries: median (P50), P90, best possible.
- Chance of reaching A or better after tier calibration.
- Strict chance to beat the best saved piece and inclusive top-three chance.
- Comparison count, scope, benchmark pieces, and partial-inventory warning.
- Parsed stats for checking OCR, source/assumption details, and Report issue.

No P25-P75 range. The mean may remain available internally but is not a primary
overlay metric. Best possible is a ceiling, not a likely result.

For a discrete distribution, define Pq as the smallest score whose cumulative
probability reaches q. P90 is not a promise of an exact 10% exceedance chance.
At +20, all projected quantiles collapse to the finished score.

### Tier calibration gate

| Tier | Intended interpretation |
| --- | --- |
| S | Exceptional for at least one supported realistic use |
| A | Strong with a clear use |
| B | Useful but replaceable |
| C | Marginal or narrowly useful |
| D | Poor fit for the supported uses |

These are qualitative definitions, not approved numeric cutoffs. The evaluation
workstream must propose and test boundaries across Crit, HP, DEF, EM, ER, and
support roles before the parent enables user-facing grades. Unknown coverage
must have an ungraded state, not D. Grade by role and relevant slot constraints;
do not compare raw scores across incompatible profiles.

Grade quality separately from account redundancy. An A piece may add little to
an established collection; a B piece may fill a gap. Preserve current-profile
screening for future uses not represented by current character guides.

No minimum upgrade probability has been chosen. Expose long-shot odds without
inventing an automatic discard threshold or labeling every possible win worth
upgrading. A rare main stat and missing benchmarks need context, not a verdict.

## Character recommendations and data

Use versioned local role definitions with source links, retrieval dates, and
explicit coverage. A role needs eligible main stats by slot, set preferences,
useful substats, and conditions such as ER goals, weapon effects, or team needs.
Keep build variants distinct internally and avoid filling the list with several
variants of the same character.

Guide priorities are ordinal, not damage weights. Treat any numeric screening
weights as an explicit heuristic. Do not claim exact damage improvement without
a complete build and its assumptions. A lack of ER on one artifact does not
prove the full build lacks ER; Crit caps also depend on the full build.

Compare saved +20 pieces of the same slot and main stat under the same role
model. Distinguish same-set and off-piece pools. Exclude the candidate itself
and preserve explicit inventory duplicates and tie semantics. Main-stat
alternatives are not interchangeable without build context.

Review data-reuse terms before bulk extraction or redistribution. Do not scrape
guides on each OCR read. Start with a reviewed coverage sample spanning different
roles, publish its gaps, and expand after calibration. Do not ship a claim of
complete roster support from a partial dataset.

## Local diagnostic reports

The user needs enough evidence for an agent to reproduce a bad reading,
flickering result, bad recommendation, or wrong overlay placement.

Report flow:

1. Open Report issue from the overlay or main window.
2. Freeze available evidence before changing the game screen.
3. Select the issue type and optionally enter the expected reading or a note.
4. Preview included images and metadata.
5. Save a local bundle and reveal its location for an explicit handoff.

Include versioned, timestamp-linked evidence:

- Exact OCR input crops with geometry and capture dimensions.
- OCR text, bounding boxes, confidence, parser errors, and confirmation decisions.
- Parsed artifact, displayed result, and reading state for the same sample.
- App/build version and relevant settings.
- Scoring/data version and comparison pieces used for recommendation reports.
- Display/window geometry for placement reports, without unrelated screen images.
- User correction and an agent-readable replay description.

The rolling buffer reuses existing reads. It must not initiate capture or OCR.
Initial design budget: up to 10 seconds, about 20 samples at the current rate,
with a 24 MiB retained-image limit. Evict oldest evidence when the budget is
reached and report actual retained duration. Store crops, not full game frames
or references that retain their full backing buffers. Duplicate suppression is
optional and must preserve sample timestamps and state transitions.

Measure CPU, memory, and OCR latency with buffering on and off before enabling
it by default. Provide a buffer-off setting. No continuous disk writes or video
encoding. Encode images on explicit save, off the capture/OCR path. Disabling
the reader clears its buffer. Completed reports stay until the user removes
them; do not silently delete saved reports.

No automatic upload, audio, or capture of other monitors. Preview crops because
they can still contain identifying text. Full game-window sequences require an
explicit recording action and a UID/chat warning. The existing 40-frame local
recorder can remain during transition; do not create two competing recorders.

Replay must use the real OCR/parser path and timing semantics. A proposed fix
should demonstrate failure on the saved case, then success, before the case
becomes a regression test. Diagnostics must not silently correct live readings
or mutate inventory from a user's annotation.

## Workstreams and ownership

All work uses this existing checkout because the current app is uncommitted:
`~/.t3/worktrees/gi-artifacts/t3code-492a9a6a`.
Do not edit the empty project-root checkout or create a worktree missing these
files. Preserve unrelated changes. No commits, branches, PRs, or pushes in this
phase. No child thread may launch/restart the app or control the game.

| Workstream | Owned changes | Handoff |
| --- | --- | --- |
| Runtime and overlay | App.swift, Model.swift, Views.swift, Capture.swift; new runtime/overlay files and dedicated tests | Placement, compact shell, shortcuts, real stop/resume, lifecycle tests |
| Evaluation | Potential.swift; new LoupeCore evaluation files and dedicated tests; docs/evaluation-design.md | P50/P90/max API plus sourced matching/tier calibration proposal; no unreviewed grades |
| Diagnostics | FrameRecording.swift; new diagnostic files and dedicated tests; docs/diagnostics-design.md | Bounded buffer/export/replay components and explicit integration contract |
| Parent | This plan, dispatch briefs, README and final shared integration | Review evaluation rules, wire diagnostics and evaluation, verify end to end |

Children must not edit each other's owned files, shared Package.swift/Makefile,
existing shared tests, or README. Ask the parent for an unavoidable shared edit.
Diagnostics supplies hooks for the runtime owner/parent rather than patching
Capture.swift or Model.swift concurrently. The overlay owner uses current
evaluation APIs until the evaluation handoff is reviewed.

Use separate temporary Swift build/scratch directories to avoid concurrent
SwiftPM locks. Format only owned changes. Report commands run, results, changed
files, blockers, and integration requirements. A dispatched or completed T3 turn
is not proof of integrated or live-tested behavior.

### Dispatched T3 threads

Started on 2026-09-26 in the gi-artifacts project. These references identify
delegated work, not completed features.

| Thread | Reference | Brief |
| --- | --- | --- |
| Overlay controls and capture lifecycle | `local:f48e96b3-d703-4f22-98d0-b7f7945cda5c` | [Runtime brief](tasks/runtime-overlay.md) |
| Character matching and tier calibration | `local:68631dad-05db-4b8b-9b9d-171ce700ea75` | [Evaluation brief](tasks/evaluation.md) |
| Local diagnostic reports and replay | `local:8b0fd1d7-f324-485e-b8ac-b93e8b6a9756` | [Diagnostics brief](tasks/diagnostics.md) |

Evaluation handoff received 2026-09-26: `Potential.summary` supplies P50, P90,
and best-possible scores. The parent reviewed the implementation and passed the
API to the overlay owner. The agent reports 39 core tests passing; package-wide
and live verification remain pending. [Character matching and tier proposal](evaluation-design.md)
is ready for review. No matcher, role dataset, or numeric grade boundaries have
been integrated.

Diagnostics handoff received 2026-09-26: bounded evidence storage, local export,
and report reading are implemented without runtime hooks. The parent reviewed
the components; the agent reports 13 diagnostic tests passing. See the
[integration contract](diagnostics-design.md). Buffering remains disabled.
Inventory currently sends the full window to Vision, so crop-only Inventory
reports must disclose partial replay coverage. Preserve that reader initially;
explicit full-window recording remains available when needed. Enhance's exact
prepared-input hook, real-path replay, UI preview, disable cleanup, and measured
overhead remain integration gates.

Runtime handoff received 2026-09-26: compact/expanded placement, configurable
shortcuts, disabled capture lifecycle, and quantile display are implemented.
The agent reports a full test run passing; recorded fixtures and live checks
were not part of that run. Automatic shared-window identity requires macOS
15.2 or later; older systems retain manual input only. The user's Mac reports
macOS 27.0, so this does not block its live verification.

Runtime ownership is now released. The diagnostics thread has the shared app
files for a sequential [integration follow-up](tasks/diagnostics-integration.md).
The parent retains README, plan, and final validation ownership. This replaces
the initial child-file restrictions only for that follow-up. The other two
child workstreams are complete and must not edit these files concurrently.

Diagnostic integration handoff received 2026-09-26. Shared Enhance OCR/replay,
partial Inventory crops, parser/display linkage, and report preview/save are
connected. Schema version 2 replaces the unintegrated version 1. Buffering is
off at each launch. The agent reports both original recorded fixtures and
buffer-off/on/replay agreement passing. Ownership has returned to the parent
for final checks. Native report interaction and live performance remain gates;
the character matcher and tier cutoffs are still unimplemented.

Parent verification: `make check` and `make app` passed. Both recorded fixture
checks passed independently: circlet 39/40 and plume 38/40 recognized, identical
counts with buffering off, on, and replay, and no post-acquisition clearing.
The built app is at `dist/Loupe.app`. Native inspection could not access
its window (`cgWindowNotFound`), although the app inventory reported it running.
Live sharing, native report/save interaction, monitor placement, and performance
verification are still pending. Buffering remains off by default.

## Acceptance and rollout

1. Verify lifecycle and placement first. Disable must stop new OCR and collection;
   rapid toggles and late callbacks must not restart it or publish stale results.
2. Test shortcut conflicts, held keys, fullscreen, multiple monitors, window moves,
   display removal, and display scaling. Confirm the panel stays click-through
   outside its controls and does not steal focus.
3. Review the evaluation proposal before wiring grades and character matches.
   Test quantile boundaries, point masses, ties, no benchmarks, candidate exclusion,
   special upgrade rules, and incompatible or unsupported role data.
4. Integrate diagnostic hooks after runtime ownership is released. Test byte/time
   eviction, disable cleanup, timestamp linkage, report read/write errors, and
   replay with no network access or extra OCR for buffering.
5. Run project formatting/lint, tests, and app build. Replay the existing circlet
   and plume fixtures; do not weaken their identity or stability assertions.
6. Coordinate one live check in the parent thread, without spending anything.
   Measure enabled/disabled CPU and memory, then buffering overhead. Record
   performance observations rather than promising unmeasured savings.
7. Update user instructions and privacy text to match shipped behavior. Do not
   claim screenshots are never retained once opt-in buffering/reporting exists.

Exact tier cutoffs, complete character coverage, buffer-default performance,
macOS capture-resume behavior, and final compact dimensions remain review or
measurement gates. Full build optimization and adaptive OCR are outside this
iteration.

## Research supporting the design

- [Akasha artifact ranking](https://akasha.cv/artifacts?filter=%5Bregion%5DASIA):
  CV is a limited artifact-ranking shortcut, not universal usefulness.
- [Akasha example leaderboard](https://akasha.cv/leaderboards/1000005100/):
  rankings have weapon, team, rotation, and ER assumptions.
- [Genshin Optimizer](https://frzyc.github.io/genshin-optimizer/) and its
  [upgrade-probability work](https://github.com/frzyc/genshin-optimizer/issues/430):
  build improvement is a different question from an isolated roll score.
- [Prydwen Furina guide](https://www.prydwen.gg/genshin-impact/characters/furina):
  set, main-stat, and ER choices depend on context.
- [Prydwen Kuki profile](https://www.prydwen.gg/genshin-impact/characters/kuki-shinobu):
  roster pages do not all contain complete build recommendations.
- [KQM Kuki guide](https://keqingmains.com/q/shinobu-quickguide/): a supplemental
  source for role-specific recommendations where coverage is incomplete.

Research was reviewed on 2026-09-26. Recheck sources before encoding guide data.
