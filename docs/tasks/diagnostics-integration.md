# Diagnostic integration follow-up

The runtime and evaluation workstreams have released ownership. Integrate the
existing diagnostic components into the real reader and a working report UI.
The parent reviewed the components and is coordinating this follow-up under
the user's authorized overlay work. Read the parent plan and both handoff docs.

## Ownership and limits

Work in `~/.t3/worktrees/gi-artifacts/t3code-492a9a6a` only.
You now own the necessary integration edits in Capture.swift, LiveCardOCR.swift,
Model.swift, Views.swift, App.swift, and OverlayPlacement.swift, plus diagnostic
files and dedicated integration tests. Do not change LoupeCore, shortcut or
capture-runtime implementations, Package.swift, Makefile, README, or this plan.
The parent owns README and final validation. No other agent is writing code.

Do not launch, stop, replace, or control the running app/game. No new screenshots,
inventory modifications, commits, branches, PRs, pushes, or further delegation.
Keep buffering disabled by default until measured in the live app. Preserve
the explicit 40-frame recorder and its privacy warning. Follow the existing
skills and normal approval flow; do not weaken tests or bypass privacy prompts.

## Required result

1. Connect the bounded buffer to existing OCR reads, with no extra capture/OCR.
   Make the opt-in setting visible and disclose its actual retained coverage.
2. Extract the minimum shared prepared-input boundary for Enhance OCR and replay.
   Preserve recognition configuration, crop mapping, normalization, confirmation,
   and parser behavior. Use the same retained pixels as the actual Vision input
   when claiming exact input replay. Disabled buffering must avoid its copy cost.
3. Preserve the Inventory full-window reader for now. Retain only a safely found
   artifact crop, or metadata if no crop is known. Clearly mark Inventory reports
   as partial; never retain the full window automatically. Do not introduce a
   new Inventory crop detector just to fill the diagnostic buffer.
4. Link sample/session identities through parser and confirmation decisions,
   displayed/stale results, delayed evaluation, and relevant comparison pieces.
   Include app/build/pipeline versions and available placement geometry. Avoid
   saving unrelated inventory or account data. State missing initial confirmation
   or Inventory context as replay limitations instead of faking complete replay.
5. Add Report issue to the main window and the overlay control strip. Freeze
   evidence before moving focus, then present one preview with editable issue
   type, expected reading, and notes. Show every retained crop and metadata plus
   the privacy warning. Saving requires an explicit local destination. Reveal
   the saved folder. Corrections remain annotations, not live inventory changes.
6. Handle no evidence/buffer off with an actionable explanation, not a false
   successful report. The user can opt in and reproduce, or explicitly start the
   existing full-window recording. Do not silently enable capture when reporting.
7. Clear reader evidence and unsaved preview references on disable/session change.
   Preserve generation guards and ignore late callbacks/freezes. Hold one preview
   and one exporter; release the preview before resuming opted-in collection.
   An explicitly started save may finish; never delete completed reports.
8. Add a replay entry point using the real shared OCR path and recorded times.
   It must distinguish OCR replay from parsing saved text. Test evidence-enabled
   and evidence-disabled readings against each other, not just serialization.

Keep the integration small. Do not add an extra recorder, background uploader,
automatic correction, full-build optimizer, or adaptive sampling. Numeric tiers
and character data are outside this follow-up. Leave the reviewed P50/P90/max
display in place. Avoid creating UI controls that have no working action.

## Checks and handoff

Use an isolated temporary Swift build/cache directory. Run full tests plus both
existing recorded Enhance regressions through the normal approved Vision path.
The user previously authorized these saved local fixtures; do not upload or
include their pixels in source control:

- `~/Library/Application Support/Loupe/Diagnostics/0EE0602D-0194-41BB-BDF0-79984F8F2200`
- `~/Library/Application Support/Loupe/Diagnostics/43BA464C-192C-4BE6-81DF-9C78711ECC1C`

Each contains expected.txt and PNG frames. Preserve the >=95% reading, identity,
and no-post-acquisition-clearing assertions. Add integration checks for disable
during preview/freeze, stale session callbacks, annotation-only behavior,
metadata-only failures, successful export, and actual prepared-input replay.
No live performance claim from storage-only tests.

Send one completion or blocker handoff to parent
`local:56c69391-8837-4946-9407-76dacdcd050c` using your own T3 reference as caller.
Include changed files, exact checks/results, live verification still needed,
buffer settings and coverage, and any replay limitations. Then stop.
