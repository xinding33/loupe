# Artifact evaluation: quantiles and calibration proposal

Reviewed 2026-09-26. This is the original evaluation proposal. The quantile API
and a limited character/tier pilot are now implemented; see
[the pilot reference](character-pilot.md) for shipped cells, experimental
thresholds, and exclusions. Broader role data and calibration remain proposed.
This proposal covers five representative characters, not the roster. No private
inventory or new game captures were used.

## Implemented outcome summary

`Potential.evaluate(...).summary` returns a `PotentialSummary` with
`p50Score`, `p90Score`, and `bestPossibleScore`. These are final +20 scores in
the same units as `currentScore`: one maximum useful roll with weight 100 is
1.0. Distribution keys remain integer score units, divided by 1000 for display.
`maximumScore` remains available and equals `summary.bestPossibleScore`.

The calculation sorts the existing distribution by score and selects the first
score whose cumulative probability reaches 0.5 or 0.9. It does not interpolate
between possible outcomes. For masses 0.75 at 5 and 0.0625 each at 5.7, 5.8,
5.9, and 6, P50 is 5, P90 is 5.9, and best possible is 6. Strictly exceeding
P90 has probability 6.25%, not necessarily 10%.

The ordinary-roll model is unchanged: each remaining random event chooses one
of four substats and one of four tiers. A known unactivated stat contributes
to final scores and consumes its activation event; it does not contribute to
the current score. Unknown fourth stats and special rules still throw. At +20
the distribution is a point mass and all three summary scores equal the
current score. An unfinished artifact with no useful substats also has a point
mass. No benchmark is needed to calculate these outcomes.

No existing ranking semantics changed. Inclusive rank probabilities count ties;
`chanceToBeatBest` requires a strict improvement. The API adds no grades,
character identities, or automatic upgrade/discard threshold.

## Source sample and coverage

The following are short paraphrases of the exact linked guide sections read
on 2026-09-26. Source update markers are not retrieval dates or guarantees of
current coverage. Crit means Crit Rate and Crit DMG; ER means Energy Recharge;
EM means Elemental Mastery. Flower and plume main stats are fixed by slot.

| Proposed standard role | Guide-supported main stats (sands; goblet; circlet) | Set and useful-stat evidence | Source update marker |
| --- | --- | --- | --- |
| Furina, off-field HP damage and Burst support | ER or HP%; HP% or Hydro; Crit | Golden Troupe for personal damage; Tenacity when team ATK support is more valuable. Meet ER needs before offensive investment; then Crit and HP%. | [Prydwen Furina, Build and Energy sections](https://www.prydwen.gg/genshin-impact/characters/furina), September 25, 2026 |
| Itto, on-field DEF damage | DEF%; Geo; Crit | Husk of Opulent Dreams. ER until the requirement, then Crit, DEF%, and lesser ATK%. | [KQM Itto, Artifacts](https://keqingmains.com/q/itto-quickguide/), version 5.6; its set-comparison calculations are marked version 3.1 |
| Xiangling, reverse Vaporize Burst damage | ER, EM, or ATK%; Pyro; Crit | Emblem of Severed Fate. ER until the requirement, then Crit, ATK%, and EM; EM's value depends on reactions. | [KQM Xiangling, Artifacts](https://keqingmains.com/q/xiangling-quickguide/), version 4.5 |
| Kuki Shinobu, Hyperbloom trigger | EM; EM; EM | Flower of Paradise Lost or Gilded Dreams. Prioritize EM; ER and HP% are secondary utility. Do not sacrifice EM to satisfy Burst ER. | [KQM Shinobu, Hyperbloom](https://keqingmains.com/q/shinobu-quickguide/), version 5.4 |
| Kokomi, on-field healer/enabler | HP% or ER; Hydro (HP% alternative); Healing Bonus | Ocean-Hued Clam. ER until needed, HP%, then flat HP. Standard healing builds do not value Crit. | [KQM Kokomi, On-Field Healer and Flawless Strategy](https://keqingmains.com/q/kokomi-quickguide/), Luna V |

This sample spans Crit, HP, DEF, EM, ER, and healing/support objectives. It
establishes role distinctions, not approved score weights or complete build
recommendations. Older guide versions leave newer teams and equipment
unreviewed. Proposed coverage records must list these omissions explicitly.

Keep the following variants separate rather than silently broadening every
standard role's eligibility:

- Itto's DEF goblet needs abundant damage buffs; Marechaussee Hunter needs
  Furina. Plunge builds need their own role. [KQM Itto](https://keqingmains.com/q/itto-quickguide/)
- Shinobu's Quicken and pure-healer roles have different main-stat priorities;
  Favonius adds a conditional reason for Crit Rate. [KQM Shinobu](https://keqingmains.com/q/shinobu-quickguide/)
- Kokomi's off-field Skill-only support can omit ER. Burst-refresh support
  cannot assume that. Bloom is another role; Lunar-Charged Favonius behavior
  must not leak into the standard healer. [KQM Kokomi](https://keqingmains.com/q/kokomi-quickguide/)
- Xiangling without relevant reactions must not inherit EM priority from
  reverse Vaporize. [KQM Xiangling](https://keqingmains.com/q/xiangling-quickguide/)

Guide advice and usage popularity are separate evidence. Prydwen's Furina page
reports much higher Golden Troupe usage than Tenacity usage, while recommending
Tenacity in some team-support contexts. Its statistics describe Enka-connected
profiles, not optimal builds. Statistics were updated September 23, 2026;
they are not calibration labels. [Prydwen Furina](https://www.prydwen.gg/genshin-impact/characters/furina)

Prydwen's [Shinobu page](https://www.prydwen.gg/genshin-impact/characters/kuki-shinobu)
is a profile/statistics page, updated August 5, 2026, with statistics updated
September 23. It does not supply the same build-guide coverage as Furina.
The KQM role recommendations fill that specific gap; popularity does not.

## Small local role-data schema

Use a versioned, reviewed local data file. Do not fetch guides during OCR.
The following schema is a proposal, not a new production parser or matcher.

| Record/field | Type and meaning |
| --- | --- |
| Dataset | `schemaVersion`, `dataVersion`, review date, explicitly covered role IDs, excluded roles and content versions |
| Role identity | Stable `characterID` and `roleID`, display name, objective, `standard` or `conditional` presentation group |
| Main-stat eligibility | Map of each `Slot` to allowed `Stat` values; each alternative can reference a condition and a source |
| Set fit | Entries with set ID, required piece count, `preferred` or `alternative`, source, and activation/team conditions; off-piece eligibility remains independent |
| Useful stats | Entries with `Stat`, purpose (`core`, `energy`, `healing`, `proc`, or `secondary`), ordinal priority group, conditions, and source |
| Conditions | Typed requirements for team, weapon/refinement, constellation, rotation/Burst use, or build totals; source-backed numeric ranges retain their assumptions |
| Evidence | Source URL, section, publisher, source version/date if present, retrieval date, `guide` or `inference` provenance, short original rationale |
| Uncertainty | `reviewed`, `needsContext`, or `unsupported`, with a reason; unknown is not a failed condition |
| Calibration | Optional approved calibration ID and version for the role/slot/main-stat cell; absent means ungraded |

Use explicit IDs and stat enums, not character names or prose as join keys.
At data load, reject duplicate role IDs, invalid slot/main-stat pairs, missing
source references, and unsupported schema versions. These checks protect the
reviewed data boundary; they do not imply the entire roster is known.
Useful-stat priorities are ordinal. They must not silently become percentages.

A runtime condition evaluation should return `met`, `notMet`, or `unknown`.
For example, a Burst ER requirement belongs to the complete build and rotation.
An artifact without ER does not prove a build fails it. Save the assumption
used for any conditional assessment so it can be explained and reproduced.

### Matching and distinct character ranking

The smallest matcher first checks slot/main-stat eligibility and evaluates
role conditions. It then describes set fit and useful substats. Ownership
must not filter the candidates: unowned characters are valid future uses.
Do not require a preferred set to show a strong off-piece.

An artifact from a preferred set is an on-set candidate, not proof of an active
four-piece bonus. An off-piece match assumes the other slots can supply the
required set. Without a full loadout, state that condition. Do not charge an
invented numeric set penalty, or assume five unrelated pieces can all be used
as off-pieces in a four-piece build.

Before cross-role calibration, show matching reasons without a strength order.
After review, rank standard credible matches by approved role-specific quality,
then confirmed versus unresolved conditions and set fit, with stable IDs to
resolve display ties. Never sort different profiles by raw roll score. A
conditional variant can be shown under more matches with its requirements.

Evaluate variants internally, then group by `characterID`. Keep one leading
standard role per character and attach its alternatives. Return up to five
distinct characters, including fewer or none when appropriate. Do not pad the
list with speculative variants. Keep the current user-selected profile
available as a separate screen for uses outside guide coverage.

Current fit uses activated substats and the current main-stat level. Potential
fit keeps the same set and main-stat type, uses +20 main-stat magnitude, and
uses the ordinary distribution for substats. A promising ceiling does not make
the current piece strong. Name the same role when showing its current, P50,
P90, and best-possible result. Selecting the best role independently for each
quantile would describe no single build and can mislead.

## Tier calibration for review

Adopt role/slot/main-stat calibration cells, with separate objective variants
where conditions change stat value. Grade intrinsic quality for that stated
use; display account competitiveness separately. An established account can
have several better pieces without changing the candidate's intrinsic grade.

The intended labels are S (exceptional), A (strong with a clear use), B
(useful but replaceable), C (marginal or narrow), and D (poor for that supported
use). Missing coverage or unresolved calibration is ungraded. A rejected role
match is not a universal D artifact. A headline grade must name its supporting
role and distinguish conditional uses from standard uses.

### Proposed calibration method

1. Review valid synthetic +20 anchors within each cell, without inventory data.
2. Label them against the five definitions before choosing numeric boundaries.
3. Compare nearby roll substitutions and resolve every tier transition.
4. Check the same anchors with different ER, Crit, and set conditions.
5. Approve versioned boundaries only for cells whose labels remain explainable.

This proposes an anchor-based calibration, not a universal roll-count ladder.
Do not fill gaps between labelled anchors with an unreviewed midpoint. A cell
remains ungraded until reviewers approve its transition examples. This is the
main decision needed before production tier logic can be written.

For the initial experiment, binary core-stat weights (100 for included stats,
0 otherwise) provide a transparent useful-roll tally. One point is one maximum
roll; lower tiers contribute 0.7 to 1.0. These are heuristic weights for the
experiment, not damage coefficients, guide endorsements, or approved role data.
Keep secondary utility visible instead of inventing 50% or 75% coefficients.
An ER-needed versus ER-not-needed scenario may use different profiles, but
must not be presented as an exact ER-cap calculation.

Compare such tallies only within the same calibration cell and assumptions.
Different main stats remove different possible substats; a one-stat role also
has a different useful-roll ceiling from a four-stat role. Normalizing by the
candidate's own available stats is wrong: it can call a poor starting stat
combination exceptional simply because it cannot improve much.

KQM's calculation standards require explicit sets, main stats, ER assumptions,
and build/rotation context. They are standards for comparative calculations,
not artifact grade boundaries. Their average-roll convention also differs
from this app's maximum-roll units. [KQM Standards, revision 2.0.2, May 3, 2024](https://compendium.keqingmains.com/)

### Concrete review anchors and failure cases

All following artifacts are synthetic five-star +20 examples with nine total
substat rolls. Values use displayed rounding. Suggested labels are review
targets, not shipped grades. They test the calibration design rather than
claiming measured damage gains.

First isolate a Crit-only flower cell, independent of a character's other
useful stats. Main stat is HP. The core score counts Crit Rate and Crit DMG.

| Target label | Four substats | Core score |
| --- | --- | --- |
| S | Crit Rate 3.9%, Crit DMG 46.6%, ATK 19, DEF 23 | 7.0 |
| A | Crit Rate 19.5%, Crit DMG 7.8%, ATK 39, DEF 23 | 6.0 |
| B | Crit Rate 11.7%, Crit DMG 7.8%, ATK 78, DEF 23 | 4.0 |
| C | Crit Rate 3.9%, Crit DMG 7.8%, ATK 117, DEF 23 | 2.0 |
| D | ATK 117, DEF 23, HP 5.8%, EM 23 | 0.0 |

These anchors do not establish transitions at 2, 4, or 6, and cannot
be used as character grades unchanged. In a low-Crit-Rate build, the first
row's Crit DMG concentration need not outperform the second. A character that
values ATK, EM, or HP could use substats this particular screen ignores.

| Role/cell example | Worked assessment and calibration consequence |
| --- | --- |
| HP damage, Hydro goblet: HP 17.5%, Crit Rate 11.7%, Crit DMG 15.5%, ER 6.5% | With HP, both Crit stats, and needed ER counted, the score is 3 + 3 + 2 + 1 = 9.0. Proposed S anchor for a compatible HP-damage role. Set and build conditions still need review. It is not superior to the Crit flower merely because 9 exceeds 7. |
| DEF damage, Geo goblet: DEF 21.9%, Crit Rate 11.7%, Crit DMG 15.5%, ER 6.5% | A DEF-based core yields the same 9.0 tally. Proposed S anchor in its own cell, not an HP-role match. Changing DEF% to HP% is a useful failure test for an overly broad matcher. |
| Hyperbloom EM flower: EM 140, ATK 19, DEF 23, HP 5.8% | Six maximum EM rolls give 6.0 core points. Proposed S EM-flower anchor despite zero Crit. A blanket Crit grade would reject the intended use. |
| EM-main-stat goblet: ATK 117, DEF 23, HP 5.8%, Crit Rate 3.9% | No EM substat is legal here, so an EM-only tally is zero. For an eligible EM role, propose B as a usable main-stat anchor, not D. Review secondary healing/ER separately. A rare main stat with no saved alternatives can fill a gap without becoming intrinsically S. |
| ER-focused support, Healing Bonus circlet: ER 38.9%, HP 5.8%, flat HP 299, DEF 23 | Six maximum ER rolls give 6.0 ER points. Proposed S ER-concentration anchor when that requirement is material. If the rest of the build already supplies enough ER, its account/build value changes; do not reuse that label as a general healing grade. |
| HP/ER healer, Healing Bonus circlet: HP 11.7%, ER 32.4%, flat HP 299, DEF 23 | The binary HP/ER tally is 2 + 5 = 7.0, with flat HP shown as secondary healing. Proposed A or better anchor pending a review of support targets. It cannot promise more practical healing if the build already meets the relevant needs. |
| Crit-heavy standard-healer circlet: Healing Bonus main, Crit Rate 19.5%, Crit DMG 15.5%, ATK 19, DEF 23 | The Crit tally is 7.0, but the standard Kokomi role has no useful Crit investment. Proposed C main-stat-only anchor for that role; other characters remain eligible. This rejects the global Crit ladder. [KQM Kokomi](https://keqingmains.com/q/kokomi-quickguide/) |

For a numeric ER failure case, suppose a reviewed build needs 200% total ER and
has 180% without this slot. A 19.4% ER substat leaves it short; 25.9% clears the
assumed requirement. These are illustrative inputs, not universal character
requirements. Do not infer either total from a single card or reward unlimited
ER after the requirement. If context is missing, report ER contribution and
the unresolved condition instead of grading the build's readiness.

For a Crit-cap failure case, suppose the rest of a conventional build supplies
90% effective Crit Rate. A 19.5% Crit Rate substat contains more than the
remaining 10 percentage points. Cap-aware value depends on the complete build,
including weapon, conditional set bonuses, and buffs. Keep intrinsic useful
rolls separate from the marginal contribution in that particular build.

If source coverage does not include a role, return "No reviewed role for this
build" and leave it ungraded. For a long-shot unfinished candidate, show the
P50, P90, and ceiling without labelling every possible win worth upgrading.
No probability of success has been approved as a keep/discard threshold.

## Role-specific saved-piece probabilities

For an approved fixed additive role profile, call `Potential.evaluate` again
with that profile. Reuse the ordinary event model, not a score histogram made
for a different profile. The scalar Crit distribution cannot be reweighted
into an HP distribution because it has lost stat identity.

For integer score distribution `D`, and saved scores `b1 >= b2 >= ...`:

- Strict chance to beat best is `sum(D[s] where s > b1)`.
- Inclusive top-k chance is `sum(D[s] where s >= bk)` for an available kth
  benchmark. Tied pieces share the rank boundary.
- Once a cell's monotone tier boundaries are approved, chance of A or better
  is the mass at scores at or above its approved A boundary. Never substitute
  the P50 score or the best-possible grade for this probability.

These probabilities are relative to saved pieces under the stated heuristic.
They are not population percentiles, damage-upgrade probabilities, or a claim
that swapping this artifact improves a complete team.

An exact cap-aware or multi-stat conditional score cannot generally reuse the
existing scalar histogram. The underlying ordinary outcomes would need to
retain their stat totals before applying that score. That is a separate model
extension, not implemented here. Until reviewed, either show fixed-profile
screening with its assumptions or mark conditional rank odds unavailable.

### Comparison contract

Use saved +20 artifacts of the same slot and exact main-stat type. An HP goblet
and Hydro goblet are separate pools even when a role allows both. Score every
benchmark under the candidate's same role/profile and condition scenario.
Special-rule candidates still have no ordinary odds; finished benchmark
substats can be compared without modelling how they were acquired.

The same-set pool matches the candidate's set identity. The all-sets pool is an
off-piece comparison, not a set-bonus simulation. A future "role-preferred
sets" pool would be a different operation and must not silently replace either.

Exclude the candidate's stable inventory ID. When a new reading has a temporary
ID, pass its linked saved ID through `excluding:`; the existing API excludes
that ID instead of its default candidate ID. Callers must resolve one inventory
identity, not pass both representations as different saved artifacts. Preserve
explicit identical copies with distinct IDs. Do not deduplicate by score or
signature during ranking, and do not change inventory import rules here.

With zero benchmarks, use "No saved +20 pieces with this slot and main stat".
Strict-best and rank odds are unavailable, not zero or 100%. With one or two
benchmarks, show the available ranks and "Only N comparable pieces saved";
the current API does not manufacture a third benchmark. Once three exist,
show inclusive top-three odds against the third score. Stable UUID order only
chooses display order among tied leaders; it does not break probability ties.

Example: candidate outcomes `{5: 0.75, 5.7: 0.0625, 5.8: 0.0625,
5.9: 0.0625, 6: 0.0625}` against saved `[6, 5, 5]` give 0% strict-best,
6.25% inclusive top-one, and 100% inclusive top-three. The two 5-score copies
count separately. Excluding one candidate-linked record can change that pool
and must happen before choosing rank boundaries.

Always show the comparison count, role/profile version, same-set or off-piece
scope, and "Compared with saved pieces only; inventory may be incomplete".
An intrinsic A with several better saved copies remains A with low account
competitiveness. An intrinsic B can still fill an empty slot. Do not silently
limit matching to owned characters or already equipped pieces.

## Source reuse and approval decisions

Prydwen's terms, updated March 2026 and read September 26, limit use to personal,
non-commercial access, prohibit bulk extraction, and restrict commercial
redistribution. Do not implement a roster scraper. Resolve permission for any
packaged derivative role dataset before release. This is a source-reuse review
gate, not a claim of a redistribution license. [Prydwen Terms of Service](https://www.prydwen.gg/terms)

KQM guides request links when used as references. That request alone does not
establish permission to redistribute their text, images, spreadsheets, or a
bulk-derived database. This proposal uses short original summaries and source
links; it includes no guide images or copied tables. Confirm the intended
distribution model and necessary permissions with the source owners before
expanding beyond this local review sample. [KQM Itto attribution notice](https://keqingmains.com/q/itto-quickguide/)

Before integrating tiers, the parent needs decisions on:

- Which sample roles and conditional variants receive reviewed coverage first.
- Whether the proposed binary screening experiment and anchor labels are useful.
- Per-cell tier transitions, secondary utility treatment, and required context.
- How to display unresolved ER/Crit conditions without implying build readiness.
- Data-reuse permission, attribution, and responsibility for version reviews.

Until those decisions are complete, integrate the quantile summary and retain
ungraded role explanations. No matcher, role-weight dataset, or tier cutoffs
are part of this implementation.
