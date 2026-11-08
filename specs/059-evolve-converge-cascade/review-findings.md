# Deep Review Findings

**Date:** 2026-11-06
**Branch:** 059-evolve-converge-cascade
**Rounds:** 1 (one autonomous fix round)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, stage 7/8 review-code)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 3 | 3 | 0 |
| Minor | 2 | 0 | 2 |
| Notable | 4 | - | 4 |
| **Total** | **9** | **3** | **6** |

**Agents completed:** 5/6 internal (Goal Alignment skipped: no PR) + 2 external tools (CodeRabbit, Codex). Copilot skipped (disabled in config).

This is a prose/instruction feature. "Code" is the edited agent command/doc Markdown plus the constitution. Findings judge whether the instruction prose faithfully and unambiguously implements the spec (FR-001..FR-028, SC-001..SC-007) and the exact marker/hand-off contract (`contracts/markers-and-converge-handoff.md`). External findings were verified against the spec before being treated as actionable.

## Findings (fixed)

### FINDING-1 (Important) — Stale worked examples and legacy auto-update sections contradicted the flow-back cascade
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md (Examples 1-3 at ~382-525; decision flow ~204-214; Thresholds ~230-234; Classification "Minor (Auto-Update Eligible)" ~566)
- **Category:** correctness / architecture / test-quality
- **Source:** correctness-agent, architecture-agent, test-quality-agent (3 independent agents)
- **Resolution:** fixed (round 1)

**What was wrong:** The normative sections correctly implement the flow-back model, but the retained legacy examples and auto-update guidance still demonstrated pre-flow-back behavior: Example 1 writes a meaning-changing spec update in place with an ad-hoc `Changelog:` line (no supersede marker, no `## Revision Notes`); Example 3 patches a Critical fix-code deviation directly with no `/speckit-converge` and no traced task; the decision flow, Thresholds, and "Minor (Auto-Update Eligible)" list permit auto-updating Minor spec changes. These contradict the new line-237 restriction, the spec Assumption ("auto-update applies only to Trivial changes and wording clarifications; a SUPERSEDED/RETIRED marking always needs the user's decision"), and FR-002/FR-003/FR-005/FR-008.

**Why it matters:** Worked examples strongly anchor agent behavior. An agent pattern-matching on these legacy sections would silently patch or auto-supersede a completed-task feature, defeating the feature's purpose and violating SC-001/SC-002.

**How it was resolved:** Added scoping caveats (not rewrites) that bound the legacy content to the pre-implementation path: a banner over the Examples section, a post-implementation restriction after the decision flow, a caveat under Thresholds, and a caveat under "Minor (Auto-Update Eligible)". Each cross-references the section-5 flow-back cascade and states that a SUPERSEDED/RETIRED marking always needs the user's decision.

### FINDING-2 (Important) — ID-less `**SUPERSEDED**` marker not recognized by downstream filters and the evolve guard
- **File:** spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md:112,114; spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md:272,274; spex/extensions/spex/commands/speckit.spex.evolve.md:259
- **Category:** architecture / external
- **Source:** architecture-agent (also reported by: coderabbit)
- **Resolution:** fixed (round 1)

**What was wrong:** FR-005 and contract §1 define three marked states: `**SUPERSEDED by <ID>**` (ID-bearing), `**SUPERSEDED**` (ID-less, for acceptance scenarios / edge-case entries), and `**RETIRED**`. The review-code and verify compliance filters, and the evolve existing-marker guard, named only `SUPERSEDED by` and `RETIRED`, omitting the ID-less bare form. A superseded acceptance scenario / edge case carrying only `**SUPERSEDED**` could be counted as live and flagged (violating FR-022/SC-004 for ID-less items), and the guard might edit a bare-SUPERSEDED item (violating FR-007's spirit).

**Why it matters:** The marker contract defines three states; recognizing only two means the prose does not unambiguously implement the contract, and can produce the exact false findings SC-004 forbids.

**How it was resolved:** Added the ID-less `**SUPERSEDED**` form to both compliance-filter set-builders, both FR-022 bullets, and the evolve existing-marker guard. The FR-012 converge hand-off guidance block was intentionally left unchanged (see FINDING-4) because it is a verbatim reproduction of contract §4.

### FINDING-3 (Important) — EC9 trigger-detection ambiguity (FR-016 vs FR-017)
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md:348 (and :350 FR-016)
- **Category:** test-quality / production-readiness
- **Source:** test-quality-agent, production-readiness-agent (2 agents)
- **Resolution:** fixed (round 1)

**What was wrong:** The FR-017 implement path (line 348) detected an active ship pipeline solely by `.specify/.spex-state` present with `status: running`, then proceeded to `/speckit-implement`. The FR-016 no-implement path (line 350) applies when evolve is triggered by verify or finish, but verify and finish also run with `.spex-state` `status: running`. The literal FR-017 condition could therefore select the implement branch for a verify/finish-triggered evolve, violating FR-016 (whose whole purpose is to stop before implementation).

**Why it matters:** FR-016's "takes precedence over FR-014" guarantee rested on a cue that does not distinguish the trigger.

**How it was resolved:** Added a sentence to line 348 stating the implement path applies only when the trigger is the review-code stage itself; `status: running` alone does not select it; when the trigger is verify or finish the FR-016 path takes precedence; the trigger (which command invoked evolve), not the state flag alone, selects the branch.

## Remaining Findings (none Critical/Important)

### FINDING-4 (Minor, Ambiguous) — Converge hand-off guidance names only `SUPERSEDED by <ID>`/`RETIRED`
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md:~321; contract §4
- **Source:** coderabbit (verified against spec)
- Left unchanged. The guidance block is a verbatim reproduction of contract §4, which itself lists only `SUPERSEDED by <ID>` and `RETIRED`. The narrowness is in the contract, not the implementation; altering the block would deviate from the authoritative contract string form. Recommend the contract/guidance also mention the ID-less bare form in a future revision.

### FINDING-5 (Notable, Ambiguous) — Anti-recursion hook-skip mechanism is unoperationalized
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md:348
- **Source:** production-readiness-agent
- Line 348 requires the evolve-invoked `/speckit-implement` to "run in pipeline mode and skip its `after_implement` hooks," but names no concrete lever. Faithful to FR-017 and the clarification, which state the requirement at the same abstraction level; the mechanism lives in `/speckit-implement`, which is out of this feature's scope and unchanged. FR-014's "do not loop further" plus the stage retry limit bound the sequence. Not a defect in the reviewed prose; captured for future hardening.

### FINDING-6 (Notable) — Persistence-model matcher "first match anywhere" can mis-select from prose
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md:96-103
- **Source:** security-agent
- A constitution that mentions a model in explanatory text before the real declaration could let the non-authoritative line win. Faithful to the clarified spec ("first matching line wins; may match anywhere"). Impact is conservative (worst case picks flow-forward/living-spec, both of which still hard-guard against destroying completed-task history via the "no task complete" gate; the current constitution is unaffected). No shell-injection surface (no bash parses the constitution). Captured as a robustness idea.

### FINDING-7 (Minor, Ambiguous) — FR-025 analyze guidance slightly broader than required
- **File:** spex/extensions/spex-gates/commands/speckit.spex-gates.review-spec.md:252 (also spec-kit.md:72, evolve.md:651)
- **Source:** coderabbit (verified against spec)
- "Treat only findings about live spec items as actionable" could, read literally, suppress legitimate cross-artifact findings that do not name a live item. FR-025 as written is satisfied (it only requires stating that superseded/retired-item findings and their completed-task findings are expected and not actionable); the carve-out is not a spec requirement. Left unchanged; optional future tightening.

### FINDING-8 (Notable) — CodeRabbit "stale verification pass" suggestion is out of scope
- **File:** spex/extensions/spex/commands/speckit.spex.evolve.md:~334
- **Source:** coderabbit (verified against spec)
- No FR requires a verification-pass cache/invalidation; in the ship pipeline, verify runs after review-code. Not actionable against this spec.

### FINDING-9 (Notable) — Pre-existing help-file drift / README analyze-note parity
- **File:** spex/docs/help.md vs spex/extensions/spex/docs/help.md (command naming, unchanged lines); README.md:435 (analyze row lacks the FR-025 caveat the help files carry)
- **Source:** architecture-agent
- Pre-existing divergence on unchanged lines (out of scope). FR-025 targets agent run-sites, not README's human-facing command listing, so the README row is not required to carry the caveat. Recommend single-sourcing the two help files in a follow-up.

## Post-Fix Spec Coverage

All fix-round edits were additive (scoping caveats and extended marker lists); no requirement text or code path was removed. Step 7b (dropped-requirement check) is not triggered. All FR-001..FR-028 and SC-001..SC-007 remain covered; FR-005/FR-007/FR-022 coverage for ID-less items was strengthened.

## Test Suite Results

No test command detected (prose/instruction repository); post-fix test step was skipped.

## Goal Alignment

Skipped (no PR found for the branch).
