# Runtime and overlay workstream

Implement the runtime/overlay portion of `docs/overlay-redesign-plan.md`.
Read that plan in full before editing. The user authorized these child threads.

## Checkout and coordination

Work only in `/Users/xinding/.t3/worktrees/gi-artifacts/t3code-492a9a6a`.
T3 may start you in `/Users/xinding/src/xinding33/gi-artifacts`, which is empty.
Set command workdirs explicitly. The app is uncommitted in the first path;
do not create a clean worktree, copy to the project root, reset, or commit it.
Use normal approval flows if the shared path is outside your writable roots.

Parent: `local:56c69391-8837-4946-9407-76dacdcd050c`.
Other threads own evaluation and diagnostic components. Never edit their files.
Use bounded execution, apply_patch for edits, and the project's Swift patterns.
Follow code-craft, testing-craft, parallel-agents, and stop-slop where applicable.
Keep prose ASCII. Do not add dependencies or speculative abstractions.

## Ownership

You own existing `Sources/ArtifactLens/App.swift`, `Model.swift`, `Views.swift`,
and `Capture.swift`. New runtime/overlay files and dedicated tests are allowed.
Do not edit ArtifactCore, FrameRecording.swift, existing test files, Package.swift,
Makefile, README, or the parent plan. Coordinate an unavoidable shared edit first.

## Deliverable

- Top-right panel anchored to the selected game window's display, not NSScreen.main
  or fixed global coordinates. Handle moves, display changes, scaling, fullscreen,
  and safe bounds. Use Apple primary documentation for unfamiliar APIs.
- A compact overlay with hotkey expansion and an interactive recovery control.
  Preserve click-through outside controls and avoid stealing game focus.
- Configurable defaults: Option + backtick expands/collapses; Option + Shift +
  backtick enables/disables. Report registration failure and avoid held-key repeats.
- A real disabled lifecycle: stop capture and new OCR, cancel evaluation, ignore
  late callbacks, clear results/reader state, stop recording, and release retained
  frames. Preserve inventory/settings. Expansion alone must not enable capture.
- Resume the selected window only when macOS permits; otherwise show sharing
  guidance. Fresh verification is required. Preserve the Enhance Inventory-context
  requirement, even if that means asking the user to return to Inventory.
- Keep the current OCR sampling rate while enabled. No change detector or adaptive
  scheduling in this task. The user approved explicit disabling as the first fix.

Use current evaluation results in the shell. Do not invent character matches,
grades, percentile values, or mock data. The parent will wire reviewed evaluation
and diagnostics after handoff. Do not leave a dead Report button in the UI.

## Verification and limits

Add focused lifecycle/placement/shortcut behavior tests. Include rapid toggles,
late results, unavailable capture, and invalid/conflicting shortcut input. Use
independent temporary build/cache directories and scoped formatting so concurrent
agents do not contend for .build or reformat their work. Use the existing Swift
test targets; report macOS permission limitations rather than bypassing them.

Do not launch, quit, replace, or drive the running app/game. Do not build into
dist, spend resources, collect inventory, or save game screenshots. The parent
owns live verification and final make check/make app. No commits, PRs, pushes,
new branches, or further delegated threads.

Finish with changed files, checks and results, concrete lifecycle behavior,
remaining manual checks, and the diagnostic integration points. Do not claim
live verification from unit tests. Send one completion or blocker message to the
parent using your own T3 thread reference as caller, then stop.
