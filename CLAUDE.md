# Loupe

Scars and invariants only. Anything a grep or `--help` can tell you doesn't go here.

## Invariants

- `make check` (strict swift-format lint, then every test) and `make app` must pass. Logic that
  can be tested without the game lives in `LoupeCore`, with tests. AppKit, ScreenCaptureKit,
  Vision and event posting stay in `Loupe`.
- No third-party dependencies.
- Only Xin tags. Pushing a `v*` tag publishes a release, updates the Homebrew cask, and every
  installed copy installs it within a day.
- The bundle identifier `io.github.xinding33.loupe` never changes. The Accessibility grant,
  settings and the cask hang off it. `Migration` carries data over from the old
  `local.artifactlens` / `ArtifactLens` names; keep it until no Artifact Lens install is left.
- Only `scripts/release.sh` stamps `LoupeBuild` = `release`. Local builds are signed with the
  same Developer ID, so that key is what stops a release overwriting one.
- The repo is public. Keep account emails, tokens, machine names, personal config, game UIDs and
  screenshots out of commits, logs pasted into docs, and PR text.
- Character weights drafted from Genshin Optimizer or guides stay in the gitignored `local/`
  folder until a role is reviewed. `tools/weights/` only writes there.
- Grading is advice only. Nothing but auto-press sends input to the game, and auto-press only
  while its target app is frontmost.

## Departures from the macOS utility defaults

- A regular Dock app with a main window, not a menu bar accessory: the dashboard, inventory and
  report flow need a window, and the overlay is a separate panel.
- No login item. It's a tool you open to play.
- Capture uses `SCContentSharingPicker`, so it needs no Screen Recording grant. Only auto-press
  needs a permission (Accessibility).
- `make` wraps SwiftPM with `--disable-sandbox` and in-repo cache paths so agents can run it
  inside a sandbox. `scripts/build.sh` takes the same flags through `SWIFT_BUILD_FLAGS`.

## Hazards

<!-- Add each one the first time it costs a session: what happened, and what to do instead. -->
- The `LoupeTests` Vision tests fail inside a restricted process sandbox. Run them with the
  sandbox disabled.
