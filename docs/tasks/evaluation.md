# Character evaluation and tier calibration workstream

Read `docs/overlay-redesign-plan.md` in full. Implement the quantile summary and
produce a sourced proposal for character matching and tier calibration. Numeric
tier cutoffs and role weights are not approved; do not ship arbitrary grades.

## Checkout and coordination

Work only in `~/.t3/worktrees/gi-artifacts/t3code-492a9a6a`.
T3 may start in the empty `~/src/xinding33/gi-artifacts` directory.
Use explicit command workdirs and normal approval flows for the shared path.
The current app is uncommitted; do not create another worktree or copy it away.

Parent: `local:56c69391-8837-4946-9407-76dacdcd050c`.
Follow bounded execution, apply_patch, code-craft, testing-craft, parallel-agents,
and stop-slop where applicable. Preserve unrelated changes; keep prose ASCII.

## Ownership

You own `Sources/LoupeCore/Potential.swift`, new evaluation files in
LoupeCore, new dedicated LoupeCoreTests files, and
`docs/evaluation-design.md`. No changes to Loupe, existing tests,
Artifact.swift, Package.swift, Makefile, README, or the parent plan.

## Deliverable

1. Add a minimal typed summary for P50, P90, and best possible using the existing
   ordinary-roll distribution. Quantiles use the first score reaching the desired
   cumulative probability. Keep the public calculation consistent with score
   units, point masses, +20 artifacts, and current tie semantics. Do not replace
   the roll model, infer unknown fourth stats, or enable special-rule odds.
2. Research representative Crit, HP, DEF, EM, ER, and support roles using Prydwen,
   KQM, and other primary guide sources as necessary. Read the exact cited pages.
   Distinguish guide recommendations from usage popularity and your own inference.
3. Propose a small local role-data schema: slot/main-stat eligibility, set fit,
   useful stats, build conditions, sources/dates, coverage, and uncertainty.
   Explain distinct character ranking, off-piece treatment, and how current
   versus potential fit differ. Standard roles first, conditional/niche roles
   separate. Do not force five matches or claim full roster coverage.
4. Propose S/A/B/C/D calibration with concrete worked examples and failure cases.
   Separate intrinsic quality from account competitiveness. Include ungraded
   unsupported roles, rare-main-stat cases, ER requirements, Crit caps, and
   characters who do not value Crit. Guide priority order is not a damage weight.
   Explain any heuristic weights and which conclusions they can support.
5. Describe how role-specific rank probabilities reuse the ordinary distribution
   and saved same-slot/main-stat +20 benchmarks. Include no-benchmark behavior,
   ties, duplicates, candidate exclusion, and partial-inventory wording.

The written proposal is the review gate for character matching and grades. Do
not implement the full matcher, encode unreviewed thresholds in production,
scrape an entire roster, or redistribute guide content. Report source-reuse and
coverage questions. The user wants unowned characters and strong off-pieces too.
No P25-P75 range, damage-upgrade promises, or population percentile labels.

## Verification and limits

Test quantiles against hand-computable distributions and real artifact outcomes,
including +20 and discrete boundaries. Use an isolated temporary Swift build/cache
directory, existing targets, and formatting scoped to owned files. Do not edit
shared tests just to make them pass. Report source dates and limitations.

Do not open/control the game, read private inventory for examples, start/stop
the app, save game screenshots, commit, branch, publish, push, or spawn threads.
Send one completion or blocker message to the parent using your T3 reference as
caller. Include changed files, exact checks/results, API handoff, and decisions
needed before integrating tiers. Stop after the bounded deliverable.
