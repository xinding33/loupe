# Local diagnostic reports

Diagnostics are integrated into the existing reader and report UI. Buffering is
off at every app launch. The user must enable "Buffer diagnostic crops" before
reproducing an issue. Reporting never enables capture or starts recording.
The existing explicit 40-frame recorder is unchanged.

## Evidence ownership and limits

`FrameReader` owns one `DiagnosticReader` on the existing serial OCR queue.
That reader owns `LiveCardOCR` and `DiagnosticBuffer`. There is no second
capture/OCR loop, disk recorder, uploader, or diagnostic timer. The existing
freshness timer requests expiration; incoming reads and freeze also expire old
evidence.

The limits are 10 seconds and 24 MiB. The byte budget charges owned pixels and
conservative metadata costs, so metadata-only failures and equal timestamps
cannot grow an unbounded array. Image payload cannot exceed 24 MiB. Metadata
charges are not RSS measurements and can reduce image coverage. Oldest samples
leave first. A single oversized sample is rejected with a visible storage issue.

The controls show retained sample count, elapsed coverage, and image bytes.
Coverage means last retained sample time minus first retained sample time.
It does not imply uninterrupted observations or a full ten seconds. The report
also records freeze time, evicted count, oversized count, and every timestamp.

`DiagnosticPixels` owns exactly `width * height * 4` payload bytes, with a
four-byte row stride per pixel, in sRGB premultiplied RGBA8. It never retains a
source `CGImage`, `CVPixelBuffer`, or crop provider. Data-based construction also
copies storage. A 16 by 8 crop of a 1024 by 512 source owns 512 bytes and exposes
a 64-byte row stride; tests verify its reconstructed provider is also 512 bytes.
These are storage-contract checks, not allocation-rate or live RSS measurements.

## Live reader and state linkage

Each capture session has a UUID. Each opted-in read gets a sample UUID and
system-uptime timestamp, also passed to real field confirmation. Wall-clock
capture time is separate. The buffer receives each sample on the OCR queue,
including errors and metadata-only failures. No extra Vision request is made
for collection. Buffer-off reads do not create a trace or copy diagnostic pixels.

`Capture.currentSample` delivers the sample key with the existing result callback.
`Model` sends parser outcome, parsed artifact, and displayed state back to that
sample. Later evaluation results retain their triggering key. States distinguish
the triggering sample from the older verified `displayedSampleID`, which can
refer to evidence already evicted. A report frozen before a model callback can
contain an explicitly pending parser decision rather than an invented result.

Recommendation evidence includes profile weights, scoring/data versions,
comparison scope, exclusion ID, actual comparable pieces, and displayed primary
metrics. It excludes unrelated inventory. App/build/OS/pipeline versions and
relevant settings accompany the report. Placement evidence contains window,
display, overlay rectangles, selected display index, and scale, never unrelated
screen images or display names. Grades and character data remain unimplemented.

Capture's existing runtime generation checks still reject late callbacks.
Queue-local sample/session checks reject late parser and evaluation updates.
On disable or session replacement, the reader releases evidence and the report
flow drops its unsaved preview. Closing a capture frame gate also clears reader
storage on its executor. Already-running OCR may finish, but cannot publish or
retain new evidence after the gate closes.

## Exact Enhance replay, partial Inventory evidence

`PreparedCardOCR` is the shared real Vision recognition boundary for live
Enhance reads and replay. Existing crop rectangles, resize interpolation,
request revision/settings, coordinate mapping, normalization, and confirmation
remain in use. With buffering enabled, the prepared image is normalized into
owned pixels and `makeImage()` supplies those exact retained bytes to Vision.
With buffering disabled, Vision receives the original prepared image directly.
The integration tests compare both paths, not just serialization.

The trace stores raw observations before layout normalization. Vision's
normalized bounding-box estimates can extend slightly beyond an image edge.
The circlet regression exposed a valid negative x coordinate near -0.000062.
Evidence now preserves finite positive-size boxes instead of rejecting or
clipping them; confidence still must be finite and between zero and one.

Inventory still submits the full game window to its original Vision request.
After its existing anchor/card selection, diagnostics may copy the bounding
union of those selected observations. This adds no detector or recognition
pass. The crop and its mapped observations are marked `isExactOCRInput = false`.
If no safe card crop is known, the sample contains metadata only. Speculative
Enhance probe crops are discarded when routing falls back to Inventory.

Inventory reports are explicitly partial: they cannot reproduce full-window
anchor search, comparison rejection, or star detection. Automatic full-window
retention is prohibited. The existing 40-frame recorder remains available only
through its explicit user action, with a UID/chat warning.

`DiagnosticReportReader.read(from:)` validates the selected local bundle.
`DiagnosticReplay.run(_:context:)` then runs the shared real Vision recognizer
on retained Enhance pixels, maps observations through recorded geometry, and
passes the saved times through `LiveCardOCR`, `FieldConfirmation`, and the real
Enhance parser. It does not use saved recognized text or corrections as OCR
inputs. It returns separate OCR and parser results for each sample. Call it off
the live OCR queue; it does not sleep or capture screens.

Supply `DiagnosticReplayContext` only from an explicitly verified Inventory
artifact and piece name. Missing context produces parser errors, while OCR
replay can still run. Inventory and incomplete inputs are rejected as partial.
Capture-side confirmation resets are recorded and replayed. A rolling buffer
can still start after initial confirmation history was evicted, so the first
replayed decisions need not match the original acquisition. No hidden initial
context is fabricated from a correction or a later parsed artifact.

## Report UI and save lifecycle

Report issue is available in the main window, overlay control strip, and app
menu. It freezes on the existing OCR queue before activating the main window.
`DiagnosticReportFlow` allows one request and preview, checks the session both
before and after freeze, and ignores stale completion. Empty/buffer-off cases
show steps to opt in and reproduce, or explicitly record 40 full-window frames.
They do not create an empty successful report.

The preview shows every retained crop, exact/partial labels, all serialized
metadata, coverage/evictions, replay limitations, and the UID/chat warning.
It provides issue kind, sample selection, expected reading, and notes. Saving
is unavailable until every image and metadata preview is prepared. Corrections
are annotations only; this flow never invokes manual-card parsing or inventory
mutation.

Freeze pauses collection. Closing the preview releases it before resuming
opted-in collection, and only while a capture session exists. One shared
`DiagnosticExporter` rejects concurrent saves. A save already authorized by the
user can finish across disable or session replacement. Completed reports are
never automatically removed. Save errors remain visible for retry.

The user chooses a new destination with `NSSavePanel`; the exporter refuses an
existing destination even if a native replacement prompt was accepted. On
success, Finder reveals the completed folder. Serialization, hashing, and writes
run in a detached utility task, off the OCR path. Metadata preview encoding also
runs off the OCR path.

## Bundle format

Schema version 2 adds read mode, confidence/five-star status, exact-input flags,
and confirmation-reset markers to the initial component schema. Version 1 is
not accepted; no migration or compatibility reader is included for that
unintegrated format.

A bundle contains `manifest.json` plus one raw `.rgba` file per retained input.
The replay boundary is `prepared-crop-inputs-v1`. Sample UUID and input index
determine filenames; manifests cannot direct the reader to arbitrary paths.
SHA-256 covers exact raw bytes. Rows are contiguous in the order reconstructed
by `DiagnosticPixels.makeImage()`. JSON dates use Foundation reference-date
seconds; sample/state times use the saved uptime clock.

The exporter writes a private sibling staging directory, then moves it to the
chosen destination. Failed saves remove only that staging directory; cleanup
failure reports its path. The reader rejects unsupported versions, malformed
links/times/geometry, inconsistent coverage, oversized files, missing or changed
pixels, and symlinked members. Nothing is uploaded automatically.

## Verification and live gates

Dedicated tests cover buffer lifecycle, delayed/frozen sessions, annotation-only
export, metadata-only failures, exact synthetic prepared-input replay, and raw
Vision geometry. The authorized recorded-sequence regression compares buffering
off, buffering on, and Vision replay at the same saved times. It retains the
95% acquisition threshold, artifact identity checks, and zero post-acquisition
clearing requirement. Private fixture pixels are not copied into the repository.

The parent still needs live preview/save/focus checks, disable/session transitions
under actual sharing, and CPU/RSS/allocation-rate/OCR-latency comparisons with
buffering off/on. No running app or game was restarted or controlled during this
integration. Do not enable buffering by default based on storage-only tests.
