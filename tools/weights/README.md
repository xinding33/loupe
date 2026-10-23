# Role weights converter

`convert_draft.py` turns a community draft of per-character artifact preferences
(`characters.js` from [fallumina/Genshin-Artifact-Rater](https://github.com/fallumina/Genshin-Artifact-Rater))
into first-pass role-weight records for Artifact Lens, plus a review report.

## Output is local-only

The draft has no license, so nothing derived from it may be committed. The script
writes only to the gitignored `local/` directory at the repo root:

- `local/role-weights-draft.json`: one record per draft role (schema version 1)
- `local/role-weights-review.md`: counts, name matching, coverage gaps, anomalies and stat-profile groups
- `local/weights-cache/`: raw fetched inputs

Only this script and README are tracked.

## Inputs

- **Draft**: by default, the latest upstream commit touching `characters.js` is fetched
  with `gh api`. The commit SHA and git blob SHA are recorded in `sources.draft`.
- **Game data**: [Genshin Optimizer](https://github.com/frzyc/genshin-optimizer) (MIT) at a
  pinned commit (`GO_PINNED_SHA`). It supplies character keys and English names, artifact
  set keys and names, and Lv90 base stats from `libs/gi/stats/src/allStat_gen.json`.

## Running

Requires Python 3 (standard library only) and an authenticated `gh` for fetching.

```sh
python3 -I tools/weights/convert_draft.py
```

Options:

- `--draft PATH`: use a local `characters.js`. The script still looks up the upstream
  commit if the file matches it; you can also pass `--draft-commit SHA`.
- `--go-dir DIR`: use pre-fetched Genshin Optimizer files instead of fetching them.
- `--go-ref SHA`: fetch a different Genshin Optimizer commit.
- `--weapon-atk N`: the assumed weapon base ATK (default 608).
- `--refresh`: re-fetch cached inputs.
- `--offline`: never call `gh`. Requires `--draft` and `--go-dir`.

The script checks its base-stat extraction against known values (Furina HP 15307,
Neuvillette HP 14695, Raiden ATK 337) and exits non-zero if any check fails.

## Conversion rules

- **Base stats**: Lv90, ascension 6: `base × growthCurve[90] + ascensionBonus[6]`.
  Traveler variants use GO's shared `Traveler` entry.
- **Substat levels**: draft 8–10 → `core` (weight 1.0), 4–6 → `secondary` (0.5),
  0–2 → `none` (0).
- **Energy Recharge**: if the draft value is above 0, the level is `requirement` with
  weight 0. ER matters only until a build reaches its requirement, so it gets no per-roll weight.
- **Flat HP/ATK/DEF**: the draft value is kept for comparison but not used. The weight is
  derived from the matching % stat so that one max flat roll is worth what it adds
  relative to one max % roll:

  ```
  weight(flat) = weight(pct) × flatMaxRoll / (pctMaxRoll × base)
  ```

  Max rolls: HP 298.75, ATK 19.45, DEF 23.15, HP% 5.83%, ATK% 5.83%, DEF% 7.29%.
  `base` is the character's Lv90 base HP or DEF. For ATK, it is the character's base ATK
  plus the assumed weapon base ATK (608 by default, a typical Lv90 5-star weapon; 4-star
  weapons are lower, so flat ATK is slightly undervalued for them). These records have the
  level `derived` and a `derivedFrom` block.
- **Names**: characters and sets are matched to GO keys by normalized English name, then
  by fuzzy matching (corrections are listed in the report). Traveler roles map to
  `Traveler<Element>` using the element in the role name. Common role-name typos
  (Feild, Sheild) are fixed in `roleName`; the original is kept in `draftRoleName`.
- **Flags**: each role lists issues that need human review, such as fuzzy name matches,
  unmatched sets, illegal or off-element main stats, only one crit stat valued, a flat stat
  rated in the same tier as its % stat, or no core substats.
