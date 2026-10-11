# Diagnostic report workstream

Read `docs/overlay-redesign-plan.md` in full. Build local diagnostic components
and a tested handoff contract for the parent to integrate after runtime changes.

## Checkout and coordination

Work only in `/Users/xinding/.t3/worktrees/gi-artifacts/t3code-492a9a6a`.
T3 may start in the empty `/Users/xinding/src/xinding33/gi-artifacts` directory.
Use explicit command workdirs and normal approval flows for the shared path.
The current app is uncommitted; do not create a worktree or copy it elsewhere.

Parent: `local:56c69391-8837-4946-9407-76dacdcd050c`.
Follow bounded execution, apply_patch, code-craft, testing-craft, parallel-agents,
and stop-slop where applicable. Keep prose ASCII and preserve unrelated edits.

## Ownership

You own `Sources/ArtifactLens/FrameRecording.swift`, new diagnostic files and
dedicated tests, and `docs/diagnostics-design.md`. Do not edit Capture.swift,
LiveCardOCR.swift, Model.swift, Views.swift, App.swift, existing tests, ArtifactCore,
Package.swift, Makefile, README, or the parent plan. Describe required hooks in
the handoff instead of patching another thread's files.

## Deliverable

- A versioned evidence/bundle model for wrong reads, flicker, recommendations,
  and placement. Link samples by timestamp/identity to OCR inputs, recognized
  text/confidence/geometry, parser/confirmation decisions, and displayed state.
- A bounded memory-only buffer that accepts existing OCR samples. It must never
  trigger capture, OCR, or background disk writes itself. Initial limits are
  10 seconds and 24 MiB retained images; report actual coverage after eviction.
  Own crop pixel storage so retaining a tiny crop cannot retain a full game frame.
- Explicit clearing on disable/session change. Do not silently delete completed
  saved reports or automatically apply a user's correction to live inventory.
- Local report serialization/export with user notes and expected readings. Use
  real temporary directories in tests, handle write errors, and encode off the
  live OCR path. No network dependency or automatic upload.
- Replay-friendly manifest/reader preserving timing and exact OCR inputs. Explain
  how it connects to the real existing OCR path without replacing it with a fake.
- Keep the current 40-frame recorder working while providing a clear integration
  path. Do not add a second continuous recorder or an unbounded report queue.

The runtime owner is changing Capture/Model/View lifecycle. Your components must
compile without their integration. Read these files for context, then propose
the minimum hook interface in docs/diagnostics-design.md. Do not refactor the
OCR pipeline speculatively. If exact input replay requires a boundary change,
explain it and leave that wiring to the parent.

Privacy: retain artifact crops by default. No other displays, audio, or full
game-window images unless a user explicitly starts that recording. Reports need
a preview and UID/chat warning where relevant. The parent owns UI integration.
The buffer's enabled-by-default decision waits for real overhead measurement.

## Verification and limits

Test time/byte eviction, oversized input, clear, sample/state linkage, round-trip
export, malformed reports, and save failures. Use synthetic images and separate
temporary Swift build/cache directories. Format only owned files. Report exact
checks/results and allocation findings; do not invent performance measurements.

Do not launch/restart/control the app or game, read private inventory or saved
game diagnostics, capture screens, build into dist, commit, branch, publish,
push, or spawn threads. Send one completion or blocker message to the parent
using your own T3 reference as caller, with changed files, API handoff, remaining
integration/tests, and limitations. Then stop.
