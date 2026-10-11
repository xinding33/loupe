# Experimental tier expansion review

Review `tier-expansion-review-2026-09-27.1`, approved by the parent on 2026-09-27.
The 11 Furina/Itto cells below are implemented in calibration
`experimental-reviewed-2026-09-27.1`. The four original cells retain their
cutoffs. The EM transfer review remains deferred; no other role gains grades.

## Approved implementation table

Four flower/plume cells use the existing three-core thresholds.
Seven separate two-core cells use lower B/A/S thresholds. Do not
copy the elemental-goblet ladder onto mains that exclude a core substat.
Retain the four shipped cells without changes.

Each number is an inclusive lower boundary in maximum useful-roll units.
D is below C, within a calibrated cell only. Missing calibration is ungraded.
All labels mean experimental substat concentration for the named role and
exact main, not damage, build readiness, or population percentiles.

| Existing role ID | Exact slot / main | Eligible core substats | Cell ID | C | B | A | S |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| `furina.off-field-hp` | Flower / HP | HP%, CR, CD | `furina.hp-flower` | 1.4 | 3.5 | 5.6 | 7.0 |
| `furina.off-field-hp` | Plume / ATK | HP%, CR, CD | `furina.atk-plume` | 1.4 | 3.5 | 5.6 | 7.0 |
| `itto.on-field-def` | Flower / HP | DEF%, CR, CD | `itto.hp-flower` | 1.4 | 3.5 | 5.6 | 7.0 |
| `itto.on-field-def` | Plume / ATK | DEF%, CR, CD | `itto.atk-plume` | 1.4 | 3.5 | 5.6 | 7.0 |
| `furina.off-field-hp` | Sands / HP% | CR, CD | `furina.hp-sands` | 1.4 | 2.8 | 4.9 | 6.0 |
| `furina.off-field-hp` | Goblet / HP% | CR, CD | `furina.hp-goblet` | 1.4 | 2.8 | 4.9 | 6.0 |
| `itto.on-field-def` | Sands / DEF% | CR, CD | `itto.def-sands` | 1.4 | 2.8 | 4.9 | 6.0 |
| `furina.off-field-hp` | Circlet / CR | HP%, CD | `furina.cr-circlet` | 1.4 | 2.8 | 4.9 | 6.0 |
| `furina.off-field-hp` | Circlet / CD | HP%, CR | `furina.cd-circlet` | 1.4 | 2.8 | 4.9 | 6.0 |
| `itto.on-field-def` | Circlet / CR | DEF%, CD | `itto.cr-circlet` | 1.4 | 2.8 | 4.9 | 6.0 |
| `itto.on-field-def` | Circlet / CD | DEF%, CR | `itto.cd-circlet` | 1.4 | 2.8 | 4.9 | 6.0 |

CR means Crit Rate; CD means Crit DMG. Fixed flower/plume mains remove none
of these roles' core stats, so their achievable score geometry matches their
elemental goblets. The anchors below make the extension explicit rather than
interpolating to all other cells. Main-stat rarity and farming frequency do
not enter this intrinsic screen.

The two-core anchors label 1.4 marginal, 2.8 useful but replaceable, 4.9 strong,
and 6.0 exceptional concentration. A 2.8 example puts three reasonably sized
rolls into a core stat; the 4.9 example combines four maximum rolls with a
near-maximum roll in the other core stat. At 6.0 the examples retain only one
point of headroom under the four-line cell ceiling. These are review judgments,
not mechanically proven quality labels. The neighboring examples intentionally
differ little: a letter boundary is a display convention, not a damage jump.

Reusing S=7.0 for two-core cells would require the four-line theoretical maximum
and make S impossible for three-line origins. This is a reason for separate
cells, not a bug in the existing three-core goblet thresholds. Furina HP and
Hydro goblets remain different cells; these numbers cannot choose between them.
Crit main choice, balance, and overcap still need a full build.

## Score semantics and attainable totals

`Profile.score` rounds each validated stat total to tenths of its maximum roll,
then multiplies by its binary weight. Divide the integer result by 1000 for
the displayed score. A core maximum roll contributes 1.0; the ordinary roll
tiers contribute 0.7, 0.8, 0.9, or 1.0. These are not guide damage coefficients.
Secondary ATK%, ER, and healing utility can matter despite contributing zero.

| Level | Legal active-roll totals, three-line / four-line origin |
| --- | --- |
| +0 through +3 | 3 / 4 |
| +4 through +7 | 4 / 5 |
| +8 through +11 | 5 / 6 |
| +12 through +15 | 6 / 7 |
| +16 through +19 | 7 / 8 |
| +20 | 8 / 9 |

A three-line origin spends +4 on activation and has four random upgrades
afterward. A four-line origin has five random upgrades. For a card with k
eligible core lines actually present, its all-core-hit ceiling is k+4 or k+5.
The cell ceiling uses all eligible core types, not just those on the candidate.
Do not normalize a poor starter by its own restricted ceiling. At +20, origin
can be ambiguous from rounded totals; no origin inference is needed to grade
the actual score.

| Eligible core types | Three-line / four-line cell ceilings | All eligible core lines, every random upgrade useful, all minimum tiers |
| --- | --- | --- |
| 3 | 7 / 8 | 4.9 / 5.6 |
| 2 | 6 / 7 | 4.2 / 4.9 |
| 1 | 5 / 6 | 3.5 / 4.2 |
| 0 | No scalar screen | Ungraded, no scalar comparisons |

For three core types, S=7 can be attained by a perfect three-line origin;
for two, S=6 can too. Kuki's shipped S=4.9 is attainable below
the three-line EM ceiling of 5. None of these facts proves S is a universal
minimum number of useful rolls. Roll sizes, core cardinality, main exclusions,
and omitted utility differ. The tests verify feasibility, not desirability.

## Legal +20 boundary fixtures

Every row below has four distinct substats, excludes its main, and uses nine
active rolls. The test suite constructs each cell through `Artifact`, then
checks its literal score through the real role `Profile` and `Potential`.
All values retain table precision instead of display rounding. No private
inventory, observed drop distribution, or copied guide table is involved.

### Flowers and plumes with three core types

Use HP% for Furina and DEF% for Itto in the scaling column. Zero means omit
the stat, never an actual zero-valued line. Flat DEF and ATK% fillers are legal
on both flowers and plumes and are not core stats in either profile.

| HP% / DEF% | CR | CD | ATK% | Flat DEF | ER | Score | Tier |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 5.83 / 7.29 | 0 | 0 | 29.15 | 46.30 | 6.48 | 1.0 | D |
| 8.16 / 10.20 | 0 | 0 | 23.32 | 46.30 | 6.48 | 1.4 | C |
| 19.82 / 24.78 | 0 | 0 | 17.49 | 23.15 | 6.48 | 3.4 | C |
| 20.40 / 25.50 | 0 | 0 | 11.66 | 23.15 | 6.48 | 3.5 | B |
| 23.32 / 29.16 | 5.83 | 0 | 0 | 46.30 | 6.48 | 5.5 | B |
| 23.32 / 29.16 | 6.22 | 0 | 0 | 46.30 | 6.48 | 5.6 | A |
| 17.49 / 21.87 | 7.78 | 14.76 | 0 | 0 | 12.96 | 6.9 | A |
| 17.49 / 21.87 | 7.78 | 15.54 | 0 | 0 | 12.96 | 7.0 | S |

### Scaling mains and eligible Crit circlets with two core types

For HP%/DEF% sands and Furina HP% goblets, X=CR and Y=CD. For CR circlets,
X=the role's scaling stat and Y=CD. For CD circlets, X=the scaling stat and
Y=CR. Select the exact values in the matching column. This covers all seven
cells without allowing a main stat as a substat.

| X: HP% / DEF% / CR | Y: CD / CR | ATK% | Flat DEF | ER | Score | Tier |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 5.83 / 7.29 / 3.89 | 0 / 0 | 29.15 | 46.30 | 6.48 | 1.0 | D |
| 8.16 / 10.20 / 5.44 | 0 / 0 | 23.32 | 46.30 | 6.48 | 1.4 | C |
| 15.75 / 19.68 / 10.50 | 0 / 0 | 23.32 | 23.15 | 6.48 | 2.7 | C |
| 16.33 / 20.41 / 10.89 | 0 / 0 | 23.32 | 23.15 | 6.48 | 2.8 | B |
| 23.32 / 29.16 / 15.56 | 6.22 / 3.11 | 0 | 46.30 | 12.96 | 4.8 | B |
| 23.32 / 29.16 / 15.56 | 6.99 / 3.50 | 0 | 46.30 | 12.96 | 4.9 | A |
| 23.32 / 29.16 / 15.56 | 14.76 / 7.39 | 0 | 23.15 | 12.96 | 5.9 | A |
| 23.32 / 29.16 / 15.56 | 15.54 / 7.78 | 0 | 23.15 | 12.96 | 6.0 | S |

The 1.0-to-1.4 pair is adjacent attainable scoring: one core roll is at most
1.0 and two total at least 1.4. A fabricated 1.3 fixture would be illegal.
Other pairs differ by the score grid's 0.1 step. For example, 10.50 CR is
three 3.50 rolls; 10.89 is two 3.50 rolls plus 3.89. This also shows that
B=2.8 is attainable without adding an illegal tenth roll.

### EM-only flowers and plumes: conditional transfer review

One 100-weight EM profile gives identical scores and ordinary-roll outcomes
for any character assigned that profile. This is mathematical equivalence
of the screen only; team function and utility are not equivalent.

| Candidate role, no ID assumed | Flower / plume C, B, A, S | Recommendation and unresolved utility |
| --- | --- | --- |
| Raiden, solely off-field Hyperbloom trigger | 0.7, 2.1, 3.5, 4.9 | Suitable for a later explicit pair of cells after role approval. Keep trigger ownership, character level, and Skill triggering conditions unknown. Do not inherit Burst-DPS ER or Crit priorities. |
| Sucrose, EM buff / transformative-reaction screen | 0.7, 2.1, 3.5, 4.9, conditional only | Same EM concentration math. Leave ungraded until the reviewed role and presentation explicitly preserve ER, Favonius Crit, and team/buff uncertainty. It is not a general support-quality tier. |
| Kazuha, EM support | No new grade recommended | Same EM concentration math, but an unresolved Burst ER requirement can dominate the trade. Keep numerical EM screening and utility visible without extending Kuki's quality labels yet. |

These are original inferences from the role facts, not thresholds published
by the guides. Raiden's Skill-based trigger role values EM and character level;
its coordinated attack needs a damage trigger. [KQM Raiden, version 5.7](https://keqingmains.com/q/raiden-quickguide/)
Sucrose's EM supports her buff and transformative reactions; her Burst is
generally optional, while Favonius adds Crit Rate utility. [KQM Sucrose, Luna VI](https://keqingmains.com/q/sucrose-quickguide/)
Kazuha's ER needs depend on team and weapon, and his guide prioritizes meeting
them before EM; Favonius adds Crit utility. [KQM Kazuha, version 4.6](https://keqingmains.com/q/kazuha-quickguide/)
All three were checked on 2026-09-27 in their artifact/ER and relevant Skill
sections. Newer teams, equipment, constellation variants, and build totals
were not independently reviewed. None establishes the new role IDs or eligibility.

The following generic EM-profile anchors cover both conditional numerical
proposals without creating roles. They work unchanged on HP flowers and ATK
plumes. The zero-to-0.7 pair is adjacent attainable; 0.6 EM is not legal.

| EM | ATK% | Flat DEF | ER | CD | Score | Conditional tier |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 29.15 | 46.30 | 6.48 | 7.77 | 0.0 | D |
| 16.32 | 29.15 | 46.30 | 6.48 | 0 | 0.7 | C |
| 46.62 | 29.15 | 23.15 | 6.48 | 0 | 2.0 | C |
| 48.96 | 23.32 | 23.15 | 6.48 | 0 | 2.1 | B |
| 79.26 | 17.49 | 23.15 | 6.48 | 0 | 3.4 | B |
| 81.60 | 11.66 | 23.15 | 6.48 | 0 | 3.5 | A |
| 111.89 | 11.66 | 23.15 | 6.48 | 0 | 4.8 | A |
| 114.22 | 11.66 | 23.15 | 6.48 | 0 | 4.9 | S |

## API contract and exclusions

`TierCalibration` retains its exact `(roleID, slot, main)` lookup and stores
table thresholds multiplied by 1000 as integers. Each cell has an explicit ID.
`CharacterAssessment.calibrationVersion` exposes the new calibration version.
There is no cardinality or matching-profile fallback. Binary role weights and
the grade-summary API remain unchanged. Boundary tests now check real
`CharacterAssessment` dispatch as well as the underlying numeric anchors.

At +20, use the actual profile score and a point-mass projection. Below +20,
current tier remains absent; show the fixed-role median forecast separately
from its ceiling. The legal +16 Furina HP% sands fixture has CR 15.56, CD 7.77,
flat DEF 23.15, and ER 12.96. Its outcome masses are 0.5 at 5.0 and 0.125 each
at 5.7, 5.8, 5.9, and 6.0. Median is 5.0 (A); P90 and ceiling are
6.0 (S). A maximum CR upgrade gives CR 19.45 and actual 6.0 at +20.
No ceiling becomes an earned S. Use full distribution mass for A-or-better odds.

No HP/ER-support, EM-main, or Furina ER-sands grade is proposed. An EM main
removes an EM-only profile's sole eligible core stat: retain `CharacterAssessment`
suppression of scalar potential/comparisons rather than displaying tied zeroes.
An EM-absent flower still has a legitimate zero score. Do not infer a missing
fourth stat. Crafted/Dust odds remain unsupported. No cap-aware ER, Crit,
healing, or damage claim is added; no automatic upgrade/discard action follows.

Keep manual profiles and existing source assumptions. Intrinsic cells do not
read inventory or ownership, and off-pieces remain eligible. Saved comparisons
stay same-slot, exact-main, +20, fixed-role, with linked-ID exclusion and the
selected set scope. Always show saved count, scope, and partial-coverage warning.
Do not rank unlike profiles by raw score or silently compare unlike mains.

## Sources and reuse limits

The existing Furina/Itto role assumptions and source versions come from the
local [pilot review](character-pilot.md): Furina, Prydwen 2026-09-25, and Itto,
KQM 5.6 with set calculations 3.1, reviewed there on 2026-09-26. This proposal
does not expand their guide facts. The numeric tables and labels above are
new synthetic work using local `Artifact.swift` and `Potential.swift` math.

Checked [Prydwen's terms](https://www.prydwen.gg/terms) on 2026-09-27, marked
March 2026: personal non-commercial access is allowed; bulk extraction and
commercial reproduction/redistribution are prohibited. This work is bounded
local personal review, not bulk collection or a distributable guide database.
KQM's inspected guide notices request reference links, which are supplied
above. No general reuse license was established; the attempted terms-of-service
page was unavailable. Attribution is not a license, and absent terms are not
permission to copy content. No guide prose, table, image, or spreadsheet is
copied here; only short original factual summaries are retained.

No inspected notice prohibited this limited reference use. This is not legal
clearance for collection or distribution. If broader reuse is wanted or terms
prohibit it, stop using that source and request explicit permission via
[KQM contact](https://keqingmains.com/contact-us/) or Prydwen's terms contact.
Concrete alternatives are user-authored manual profiles and independently
verified in-game facts, with provenance, instead of a guide-derived database.
No publication, upload, runtime network, or scraper is authorized or added.

## Verification

`TierExpansionAnchorTests.swift` covers all 11 approved existing-role cells,
generic EM flower/plume boundaries, both +20 legal roll budgets and their
ceilings, +20 point masses, an unfinished median/ceiling split, monotonic
useful upgrade behavior, and invalid main/roll-total rejection. It uses real
`Artifact`, existing role profiles, and `Potential`; no duplicate scoring or
grading implementation is introduced. Its six tests have 28 parameter-expanded
cases, including 104 boundary artifacts. Existing four-cell tests remain
untouched by this workstream.

`TierExpansionDispatchTests.swift` adds six tests (eight parameter-expanded
cases) for unfinished tiers, exact A-or-better mass, role-specific saved
leaders, an ungraded role with identical weights, neighboring unsupported
mains, and no-eligible-core suppression. The partial-odds fixture starts at
4.0 with masses 0.5 at 4.0 and 0.125 each at 4.7, 4.8, 4.9, and 5.0. Its
median is B and ceiling A, but its A-or-better probability is exactly 0.25.

Before runtime edits, the tier suites failed with 22 missing-grade issues,
including nil grade summaries for the new boundary and forecast fixtures.
No temporary production mutation was used. After adding the approved cells,
all 94 ArtifactCore tests in six suites passed on 2026-09-27, including the
unchanged legacy boundary tests. Swift scratch/cache paths were isolated and
`ARTIFACT_LENS_FIXTURES` was unset. Scoped strict Swift formatting and
ASCII/whitespace checks passed. No app, desktop, live OCR, private inventory,
recordings, or reports were accessed.
