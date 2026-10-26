# Loupe

A macOS overlay that tells you which Genshin Impact artifacts to keep, level or feed, while you play through GeForce NOW.

Loupe reads the game window you share with it, recognizes five-star English artifact cards, and gives each one a verdict: **Keep**, **Level to +N**, **Review** or **Fodder**, with the character it's for and one reason. It works out every possible +20 outcome, how rare the piece is among new drops, and how it compares with your saved +20 artifacts. The reader never clicks in the game, upgrades or salvages anything. Separately, [auto-press](#auto-press) can repeat one key while GeForce NOW is in front, for skipping dialogue; it stays off until you turn it on.

Loupe is a fan-made tool. It isn't affiliated with or endorsed by HoYoverse or NVIDIA.

## Install

```sh
brew install --cask xinding33/tap/loupe
```

Or download `Loupe-x.y.z.zip` from the [latest release](https://github.com/xinding33/loupe/releases/latest), unzip it and move `Loupe.app` to Applications. It needs macOS 14 or later; live capture and automatic monitor placement need macOS 15.2 or later. On macOS 14, enter card text by hand.

Loupe asks for no permission to read the game: you pick the window in the macOS sharing picker each session. Auto-press needs Accessibility access, and asks the first time you turn it on.

### Updating

Loupe checks for a new release once a day and installs it. Turn that off with **Install Updates Automatically** in the app menu, or use **Check for Updates…**. `brew upgrade` leaves it alone, because it updates itself.

Artifact Lens, Loupe's earlier name, kept its data elsewhere. On first launch Loupe moves the saved inventory and diagnostics from `~/Library/Application Support/ArtifactLens/` and imports its settings.

## Run

1. Click **Choose game window**.
2. Select **Genshin Impact on GeForce NOW** in the macOS sharing picker.
3. Select one five-star artifact in Inventory or on a character's Artifacts screen.
4. Wait for **Live card verified across two frames**.

The overlay starts compact near the top-right of the shared window's display. It follows that window between monitors. Drag the control strip to adjust its position; its reset arrow restores the corner. The strip also has expand/collapse, **Report**, and disable controls; hover for labels. The result surface passes clicks through to the game.

| Default shortcut | Action |
| --- | --- |
| Option + backtick | Expand or collapse the overlay |
| Option + Shift + backtick | Enable or disable the reader |

Edit the shortcuts in the main window and click **Apply shortcuts**. Keys use US keyboard positions. Registration conflicts appear there; the menu and main-window controls remain available.

**Collapsed** still reads artifacts. **Disabled** hides the overlay, stops capture and new OCR, cancels evaluation, and clears live results. Inventory and settings remain. An in-flight read may finish, but cannot publish results or save artifacts. If macOS cannot stop sharing, the app reports the error and keeps OCR disabled.

Enable again to reuse the selected window if sharing permission remains valid. Otherwise choose the window again. Read a fresh Inventory card before entering Enhance. Disabling also stops collection and clears an upgrade link; re-enable collection or relink explicitly when needed. Expanding alone never enables capture. Reopen the main window from the Dock.

## Auto-press

Auto-press repeatedly presses a key while a chosen app is in front. Sending inputs to an online game may break its terms of service; use it at your own risk. It comes from [Mash](https://github.com/xinding33/mash) and starts with **F** in **NVIDIA GeForce NOW**, several times a second, which talks, picks up items and skips dialogue in Genshin Impact.

1. Turn on **Press F repeatedly** under Auto-press in the main window, or press the toggle (`` ` `` to start with) while GeForce NOW is in front. A banner shows **Auto-press on** or **Auto-press off**, since the menu bar is hidden in full screen.
2. It presses only while GeForce NOW is in front. Switch away and it pauses; come back and it carries on.
3. It turns itself off after 10 minutes unless you change that.

The Auto-press panel sets the key, the toggle (a key, a key combination or an extra mouse button), the app, presses per second and the timer. The app menu has **Turn auto-press on / off**.

Auto-press needs **Accessibility** access to press keys and to use a mouse button as its toggle. It asks the first time you turn it on; until then the panel shows **Open Accessibility settings** and auto-press stays off. It notices the grant without a restart.

Key presses are `CGEvent`s posted only while the chosen app is frontmost. A keyboard toggle is a Carbon hot key registered only while that app is in front, so it never takes the key from other apps. A mouse-button toggle is an event tap. Both swallow the toggle, so the game never sees it. The toggle can't be the key being pressed or one of the overlay's shortcuts. Auto-press works whether or not the reader is enabled. Don't run Mash at the same time: both would answer the same toggle.

## Build the inventory baseline

Start with upgraded artifacts, not the whole bag:

1. Filter Inventory to five-star artifacts and sort by level.
2. Enable **Collect cards as I browse**.
3. Select each +20 artifact, including equipped pieces, and wait for verification.
4. Check the saved count and recognized stats.
5. Turn collection off before evaluating new pieces.

Alternatively, use **Import** under Saved inventory for GOOD JSON or a Loupe or Artifact Lens backup. Imports merge without deleting existing records. Repeated imports do not multiply identical records; duplicates within an imported inventory are preserved.

Screen scanning cannot distinguish two identical physical artifacts. Use **Save copy** for an additional real copy. This matters for top-two and top-three comparisons. Expand **Saved +20 coverage by slot and main stat** to find sparse comparison groups; counts do not establish that the scan is complete.

Before upgrading a candidate, save it and choose **Link upgrade** on its inventory record. Let the app verify its Inventory card, then open Enhance. Advice updates when the displayed rolls settle. Click **Update linked** to replace the saved version. If collection is enabled and a record is linked, verified upgrades update that record automatically. Unlink before switching to another candidate. Do not scan a changing inventory order as if it were an artifact identity.

**Paste / correct card text** provides a manual path when OCR cannot read the card. It stops capture so live frames cannot overwrite your correction.

## What the numbers mean

**The verdict** comes first in the overlay and dashboard: **Keep**, **Level to +N**, **Review**, or **Fodder**, with one reason. It is advice only; nothing acts in the game.

- **Keep** a finished piece when a better one would take at least 1,000 five-star domain drops for some character, or when it is B or better for a character and beats enough of your saved +20 pieces of that slot and main stat.
- **Level to +N** an unfinished piece when its exact chance of becoming a keeper at +20 clears a bar that rises from 5% at +0 to 30% at +16, because the last levels cost the most.
- **Fodder** when no character uses the slot and main stat, when it is in the bottom half of new drops for every one, when saved pieces already beat it for every one, or when its keeper chance is below the bar.
- **Review** otherwise, including good pieces with no saved +20 pieces to compare. Save your +20 pieces first (see above) so the verdicts can use them.

The character behind the verdict leads the shortlist. Defaults and measurements are in the [grading approach](docs/grading-approach.md).

**Character uses** is the default assessment. It covers every playable character through shared [archetypes](docs/archetypes.md): twelve stat profiles such as HP crit damage or EM reaction support. Each character is assigned its archetypes, the goblet it uses, and its four-piece sets. Characters in one archetype share a grade, so a role is only as specific as its archetype. 15 roles were also reviewed one by one: Alhaitham, Bennett, Fischl, Furina, Itto, Kazuha, Kokomi, Kuki Shinobu, Nahida, Neuvillette, Raiden Shogun (Hyperbloom), Sucrose, Xiangling, Xingqiu, and Yelan. They keep their reviewed details; other roles say they come from an archetype. Coverage includes unowned characters and off-pieces. See the [coverage and source limits](docs/character-coverage-expansion.md) for the reviewed roles.

The dashboard and overlay show the same shortlist of up to five potential users. The verdict's role comes first; the rest are ordered by useful-stat presence, set fit, main-stat fit, and the number of useful substats, not cross-character damage or raw scores. The five show one role per character and different archetypes before repeating one. Select a role in the dashboard to inspect its assumptions and forecast; your selection stays in the shortlist. **Show all N eligible roles** reveals the rest, including a character's other roles.

Experimental S/A/B/C/D tiers grade every role. A tier says how rare the piece's useful rolls are among every possible new five-star drop of the same slot and main stat, scored with that role's useful stats:

| Tier | Share of new drops this good or better |
| --- | --- |
| S | 0.05% or less (about 1 in 2,000) |
| A | 1% or less |
| B | 15% or less |
| C | 50% or less |
| D | the rest |

The odds are exact for domain drops: main-stat odds, a 20% chance of four starting lines, substat appearance weights, and the four roll tiers. These cutoffs were chosen to match the 15 combinations previously calibrated by hand; their B, A, and S cutoffs agree within a third of a roll. Rarity is not damage, and it ignores what you already own. Expanded details also show the share itself and the expected number of five-star domain drops, from either of the domain's two sets, before a better piece of the same set, slot, and main stat.

A piece is **Ungraded**, which does not mean bad, when no useful substat can appear on it (an EM-main piece for an EM-only role) or when there is no final score or forecast. The headline shows the median projected +20 tier for unfinished pieces and the final tier at +20. Tier badges use gold S, purple A, blue B, green C, and gray D; a dashed badge means Ungraded or no scalar grade. A small **Best** tier beside an unfinished piece is its ceiling, not an earned grade. The compact overlay adds one account line that always names the comparison scope and saved count. Expanded details show P90, best possible, and the chance of reaching A or better. See the [grading approach](docs/grading-approach.md) for the method and its validation against the earlier [original](docs/character-pilot.md) and [expanded](docs/tier-expansion-review.md) hand calibrations.

Choose **Manual profile** for other characters or stat combinations. The manual score remains available independently of character assessment.

- **All sets (off-piece):** compare the same slot and main stat across every saved set.
- **Same set:** also require the same artifact set.
- **Now:** current weighted roll score.
- **Median +20 / P90 +20:** the first possible final score whose cumulative probability reaches 50% or 90%.
- **Best possible:** maximum final score, not a likely outcome. At +20, show the final score without redundant upgrade projections.
- **Best rank:** best reachable rank in that comparison pool. Ties share rank.
- **Top N or tied:** probability of reaching or exceeding the current Nth-best score.
- **Strictly beat #1:** probability of exceeding the best score, excluding ties.

Manual profiles cover crit, ATK, HP, DEF, EM, ER, and common combinations. Presets label **Valued stats**; custom settings label **Roll weights** from 0 to 100. One maximum-sized useful roll at weight 100 is one point. Equal CRIT Rate and CRIT DMG roll weights already account for their approximately 1:2 stat amounts. These weights are not character percentages or damage multipliers.

Character profiles use fixed core-stat weights and show secondary utility separately. ER requirements and Crit caps need full-build context and are not resolved by the card. Grades describe intrinsic screening quality; stronger saved inventory does not lower a grade.

Percentiles describe the artifact's possible rolls, not its rank among other players. Discrete outcomes mean the probability of exceeding P90 need not be exactly 10%. Best possible is a ceiling, not a recommendation to spend resources on every nonzero chance.

The baseline always says **partial inventory**. Unscanned pieces can change every rank. Unfinished inventory pieces are not treated as +20 benchmarks. With no comparable +20 pieces, the app shows potential but withholds ranks and probabilities.

## Model and limits

Ordinary five-star upgrades only. The model activates a known fourth substat at +4 when necessary, then enumerates remaining stat/tier outcomes. It uses normalized 70/80/90/100% roll tiers and equal probabilities across four stats and four tiers. Displayed totals resolve to the nearest tenth of a maximum roll. The probabilities are exact for this normalized model, not exact damage or internal-stat comparisons.

Current five-star cards preview the fourth substat. If that line is missing, read or enter the stat and its value instead of guessing an unknown-stat distribution. The [starter-model reference](docs/starter-probabilities.md) records the evidence and activation tests. The +4 activation is fixed when the preview is known; later random rolls are separate.

Crafted artifacts with guaranteed rolls and Dust reshaping need a different probability model. Mark **Crafted / guaranteed rolls** before reading those cards. Visible special-rule text also disables ordinary odds, but the app cannot reliably infer provenance from every card. Unfinished GOOD imports are conservatively marked special because the import does not establish their roll rules. Their finished +20 stats can still serve as benchmarks.

The live reader targets one full artifact card, in Inventory or on a character's Artifacts screen, and the Enhance stat panel. Enhance omits set and rarity, so it requires a previously verified card in the same capture session. Item name, slot, main stat, substats, and upgrade-event count must agree. Enhance OCR reads separate title and stat-table crops at a fixed resolution. Language correction applies to the title only, not numbers.

Each Enhance field needs two matching observations within the last two seconds, using at most five frames. A missed field can use that recent evidence while other fields remain readable. A changed field blocks a new result until confirmed. A changed level resets the evidence, so the old inactive row cannot carry into an upgrade. Window-size changes and leaving Enhance also reset it. The parser removes decorative punctuation but does not infer digits or repair ambiguous decimals. Lower-confidence text can confirm an exact previously verified card, but cannot establish changed stats.

A missed reading keeps the last verified result visible for up to three seconds, labeled **Rechecking**. Saving and automatic collection pause until two consecutive readings agree again. The timeout runs from the last verified reading, not the last received frame. A different parsed card immediately hides the old result. Capture stops clear it immediately. Return to Inventory if the reader loses context; ambiguous material previews do not produce new advice.

Enhance reading can still fail when particles overlap text. Rechecking changes a small status label rather than replacing the recommendation heading. The diagnostic recorder below captures failures for local regression testing.

A **Fodder** verdict covers the archetypes each character is assigned. A piece may still have set value or a use in a build no archetype describes.

## Data and privacy

Only the window selected in the sharing picker is captured. Vision OCR runs on this Mac. The only network request is the daily update check, which asks GitHub for the latest release and sends nothing about you or your artifacts. Diagnostic buffering is off at each launch. Without opt-in buffering or explicit recording, normal reading retains no diagnostic images. Recognized inventory records are plain JSON at:

```text
~/Library/Application Support/Loupe/inventory.json
```

Writes are atomic. **Undo** under Saved inventory reverses the last inventory change during the current session. Export backups before a large scan. A damaged inventory file disables saving rather than replacing the file.

**Record 40 test frames** explicitly saves 40 PNG images from the shared window, normally about 20 seconds. They may contain your UID. The app shows the saved folder under `~/Library/Application Support/Loupe/Diagnostics/`. Recording stops after 40 frames or when capture stops. These files stay outside the repository and are never uploaded automatically.

## Report a reading or overlay problem

1. Enable **Buffer diagnostic crops** in the main window.
2. Reproduce the problem while the reader is enabled.
3. Click **Report issue** in the main window, overlay strip, or app menu.
4. Review the retained crops, metadata, and replay limitations.
5. Choose the issue type and optionally enter the expected reading and notes.
6. Click **Save local report...** and choose a new destination.
7. Share that folder with an agent only after checking its contents.

The buffer reuses existing OCR reads. It adds no capture or OCR loop and performs no continuous disk writes. Its limits are ten seconds and 24 MiB of accounted evidence, including metadata. Large crops can shorten the retained history; the controls show actual sample count, duration, and image bytes. These limits are not a promise about total app memory or measured overhead.

Reporting freezes evidence before opening the preview and pauses collection. Closing the preview resumes opted-in collection only for an active capture session. Disabling the reader, changing sessions, or turning buffering off clears buffered images and unsaved previews. Already-authorized saves may finish; completed report folders are never automatically deleted.

Reports contain timestamps, OCR inputs and observations, parser decisions, displayed results, relevant comparison pieces, settings, and placement geometry. Expected readings are annotations and never change inventory. Crops and metadata can contain identifying text. Nothing is uploaded automatically, and other monitors and audio are not recorded.

Enhance reports retain exact prepared Vision inputs for replay. Inventory reports are partial: the current reader searches the full window, but the buffer keeps only the selected card crop or metadata. It cannot replay the full-window search or star detection. Initial confirmation history and verified Inventory context can also precede the retained sequence. Use the explicit 40-frame recorder when a full-window reproduction is needed.

A saved folder contains `manifest.json` and raw `.rgba` inputs. The [diagnostic integration reference](docs/diagnostics-design.md) describes the format. The preview displays all retained images before saving; no separate image viewer is required to review them. Reports include the packaged source fingerprint and the active character/calibration versions.

Agents can use the [local replay command](docs/diagnostic-replay.md) to rerun Vision and parsing without launching the desktop app or reading its inventory. Replay compares parsed artifact identities; free-text corrections remain annotations for review.

## Build

Building needs Xcode with a Swift 6 toolchain. No external packages, accounts or API keys.

```sh
make check   # strict swift-format lint, then every test
make app     # dist/Loupe.app
open dist/Loupe.app
```

`make app` runs `scripts/build.sh`, which signs with this Mac's Developer ID certificate if it has one, so the Accessibility grant that auto-press needs survives rebuilds. Otherwise it signs ad hoc, and macOS asks again after each build. Set `SIGN_IDENTITY` to choose another identity. Builds from source never update themselves. `make format` fixes formatting.

### Release

Push a `v` tag, e.g. `git tag v0.1.0 && git push origin v0.1.0`. The release workflow tests, signs, notarizes and publishes `Loupe-0.1.0.zip`, then updates the cask in [xinding33/homebrew-tap](https://github.com/xinding33/homebrew-tap). To make a release on this Mac instead, run `scripts/release.sh`.

## Development

See [project status](docs/status.md) for what is verified and what remains open.

- `LoupeCore`: auto-press settings and timer, validated artifact data, card parsing, per-field OCR confirmation, probability distributions, and inventory persistence.
- `Loupe`: ScreenCaptureKit, Vision OCR, key posting and global shortcuts, native windows, and user workflows.
- `LoupeCoreTests`: roll events, ties, ranking scope, invalid input, imports, duplicates, upgrade identity, persistence, and live-reading stability.
- `LoupeTests`: synthetic Enhance images passed through Vision and the card parser at two resolutions, plus an opt-in recorded-sequence test. These tests need access to macOS Vision services and may not run inside a restricted process sandbox.

For a recorded Enhance sequence, put its expected Inventory card text in `expected.txt` alongside the PNG files. Set `LOUPE_FIXTURES` to that folder when running `make check`. The replay test checks card identity, requires at least 95% readable frames, and rejects any clearing of the result after initial verification. It is skipped without that environment variable. Synthetic tests alone do not establish live-reader reliability.

The core does not capture screens or depend on the UI. OCR waits for two consistent readings before enabling advice or collection.

## Research references

- [KQM artifact guide](https://keqingmains.com/misc/artifacts/): upgrade checkpoints, roll tiers, stat rounding, and the limits of crit-only evaluation.
- [Genshin Optimizer](https://github.com/frzyc/genshin-optimizer): inventory interchange through GOOD and existing artifact optimization work.
- [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos): selected-window capture.
- [Apple Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images): on-device OCR.
- [Apple fullscreen auxiliary windows](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary): fullscreen overlay window behavior.

## License

Copyright 2026 Xin Ding. Licensed under the [Apache License, Version 2.0](LICENSE). Loupe was developed with AI assistance.

Genshin Impact is a trademark of HoYoverse. Game data such as stat values and drop odds comes from community research, credited above.
