# Replay a local diagnostic report

The `replay` command runs before `NSApplication`, `AppDelegate`, or `Model`
creation. It does not open windows, register hotkeys, capture screens, load
saved inventory, or change the report. It reads only the explicitly selected
report directory and optional context file. Nothing is uploaded.

## Inputs

Use the executable inside a packaged app, not `open -a`:

```sh
dist/Loupe.app/Contents/MacOS/Loupe replay --help
dist/Loupe.app/Contents/MacOS/Loupe replay /absolute/report-directory --context /absolute/context.json
```

The report directory must contain an existing schema-2 `manifest.json` and its
retained `.rgba` members. A manifest path, empty directory, malformed bundle,
unsupported schema, or changed pixels is rejected. The command never creates,
repairs, replaces, or migrates a report.

Create the context file from an independently verified five-star Inventory card
that precedes the retained Enhance sequence. Confirm its piece name, set, slot,
main stat, level, substats, and any unactivated fourth stat. List the substats
in the card's top-to-bottom order: Enhance rejects a reading whose stats appear
in a different order, so labels read in swapped rows cannot pass. Do not manufacture
context from the report's unverified saved OCR, parsed result, or correction.

This synthetic example demonstrates the JSON format; it is not a substitute
for the context of a real report:

```json
{
  "fiveStarsConfirmed": true,
  "pieceName": "Synthetic Feather",
  "artifact": {
    "id": "98C75392-E917-4CBA-9029-4FD491C91B3D",
    "setName": "Synthetic Set",
    "slot": "plume",
    "main": "atk",
    "level": 0,
    "substats": [
      { "key": "hp", "value": 209 },
      { "key": "def", "value": 16 },
      { "key": "eleMas", "value": 19 }
    ],
    "unactivated": { "key": "critDMG_", "value": 6.2 },
    "rule": "ordinary"
  }
}
```

The artifact uses `Artifact`'s Codable format and validation. Its UUID identifies
the supplied piece within this replay; it need not come from saved inventory.
Omit `unactivated` or use `null` when no known unactivated stat exists. Use the
actual roll rule (`ordinary` or `special`). The CLI requires a nonempty piece
name containing letters and `fiveStarsConfirmed: true`. That boolean records
the caller's confirmation; it does not detect rarity or prove the input's origin.
A legal but incorrect context can still fail the real Enhance parser.

Omit `--context` to inspect fresh OCR alone. No implicit context is loaded:

```sh
dist/Loupe.app/Contents/MacOS/Loupe replay /absolute/report-directory
```

No arguments starts the normal desktop app. Use `--help` when inspecting an
unfamiliar executable. Invalid CLI arguments exit without starting the app.

## Output and exit status

Valid nonempty reports produce JSON on stdout. Argument, context, and bundle
errors go to stderr. Each sample includes its UUID, ISO-8601 capture timestamp,
saved monotonic time, mode, status, fresh OCR text/confidence or error, fresh
parsed artifact or error, saved parsed artifact, and saved parser decision.
The output also identifies the report, recorded app/build/pipeline versions,
current replay build, supplied-context state, and annotations.

`savedArtifactComparison` compares `Artifact.signature` only: normalized set,
slot, main stat, level, roll rule, substats, and known unactivated stat. It is
`same-signature`, `different-signature`, or `unavailable`. UUID differences do
not affect this comparison. A mismatch does not by itself set a failure exit;
both results remain available for inspection.

`annotation.expectedReading` and `annotation.notes` are free text. Their sample
UUID, if present, scopes the annotation. The command does not parse a correction,
apply it to inventory, or claim automatic semantic equality with the result.
Compare the fresh parsed fields with the user's stated expectation manually.

| Exit | Meaning |
| --- | --- |
| 0 | Help, or all retained samples parsed successfully. |
| 1 | At least one non-Inventory sample failed OCR/confirmation or parsing. |
| 2 | Verified context was omitted; OCR still ran. |
| 3 | Partial Inventory evidence, with context supplied and no other replay failure. |
| 64 | Invalid arguments, unreadable/invalid context, or missing five-star confirmation. |
| 65 | Invalid, unsupported, unreadable, or empty report bundle. |
| 66 | The explicit report directory does not exist. |

Missing context takes precedence over sample failures. With context supplied,
OCR/parser failure takes precedence over partial Inventory evidence. Inspect
every sample even when the command returns nonzero.

The existing confirmation algorithm requires repeated observations. Its first
retained Enhance frame normally fails while later frames parse successfully.
This command deliberately returns exit 1 for that sequence rather than hiding
the first failure. Exit 0 is therefore not the expected assertion for a normal
Enhance recording with cold confirmation history. Check the per-sample results.

## Replay and privacy limits

`DiagnosticReportReader.read(from:)` validates the bundle before
`DiagnosticReplay.run(_:context:)` reruns real Vision, field confirmation, and
the Enhance parser. Saved OCR observations, assembled text, and annotations are
never replay inputs. Replay uses the retained pixels, geometry, OCR settings,
timestamps, and confirmation-reset markers. Results can differ across Vision
or OS versions; this is not a portable OCR implementation.

Inventory crops are partial evidence. They cannot recreate the original
full-window anchor search, comparison rejection, or star detection, even when
context is supplied. Such samples report `partial-inventory`; the command does
not pretend to rerun full Inventory OCR. Missing Enhance inputs fail replay.
Confirmation history before the retained window is unavailable. Successful
Enhance parses update context through the existing replay API; failed parses
do not. A sequence that changes artifacts may require different verified context
and cannot be reconstructed by guessing from saved text.

This command does not rerun recommendations, character evaluation, or placement.
It omits report settings, display state, comparison inventory, saved OCR text,
and raw pixel data from its output. Artifact fields, fresh OCR, saved parser
decisions, version strings, limitations, and annotations can still contain
private text. Review output before sharing it. The CLI does not add input paths
to output or filesystem errors, but it does not redact user-supplied text.

## Build identity

`scripts/build.sh` (run by `make app` and releases) embeds
`LoupeBuildFingerprint` in the packaged `Info.plist` before code signing. The
value is `sha256-` followed by a deterministic content hash of all Swift files
under `Sources`, `Package.swift`, `scripts/Info.plist`, and `scripts/build.sh`.
It includes untracked sources and does not depend on Git HEAD. Only the digest
is embedded; no checkout paths are included. Keep sources unchanged during
packaging.
The fingerprint identifies relevant source content, not the compiler, SDK,
build flags, or binary integrity. Direct SwiftPM executables report
`replayBuild: "unpackaged"`; packaged replay reports its embedded fingerprint.
Older reports retain their recorded build value and are not rewritten.

## Synthetic verification

Tests use generated text images and temporary reports only. They check CLI
arguments, context validation, report errors, partial evidence, real saved-pixel
Vision/parser replay, signature comparisons, and unchanged report bytes.
Conflicting saved OCR and annotations verify that replay does not use them as
input. Existing report API tests remain separate.

Run the command tests with an isolated Swift build/cache directory:

```sh
scratch=$(mktemp -d /tmp/artifact-replay.XXXXXX)
env -u LOUPE_FIXTURES \
  CLANG_MODULE_CACHE_PATH="$scratch/module-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$scratch/module-cache" \
  swift test --disable-sandbox \
  --scratch-path "$scratch/build" --cache-path "$scratch/cache" \
  --config-path "$scratch/config" --security-path "$scratch/security" \
  --filter diagnosticCommand
```

The unset fixture variable prevents optional private recording tests from
loading recordings. No live game or desktop interaction is needed. Synthetic
tests do not verify native capture, report UI behavior, or live performance.
