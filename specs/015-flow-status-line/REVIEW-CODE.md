# Code Review: Flow Status Line

**Spec:** [spec.md](spec.md)
**Date:** 2026-04-07
**Reviewer:** Claude (spex:review-code)

## Compliance Summary

**Overall Score: 100%**

- Functional Requirements: 26/26 (100%)
- Error Handling: N/A (silent degradation per spec edge cases)
- Edge Cases: All covered (no state file, missing spec_dir, backward compat)

---

## Code Review Guide (30 minutes)

> This section guides a code reviewer through the implementation changes,
> focusing on high-level questions that need human judgment.

**Changed files:** 23 files changed (3 scripts, 1 hook, 5 speckit skills, 5 overlay guards, 8 spex skills, 1 command)

### Understanding the changes (8 min)

- Start with `spex/scripts/spex-ship-statusline.sh`: This is the core change. The script was rewritten to support both ship and flow modes with a mode dispatch at the bottom. Read `render_flow()` for the new logic and `render_ship()` to confirm ship mode is preserved.
- Then `spex/scripts/spex-ship-state.sh`: The `write_state()` function now includes `"mode": "ship"` and `verify_stage_artifacts()` was updated for split review files with [REVIEWERS.md fallback](spec.md#fr-015a).
- Question: Does the mode dispatch (lines 189-201) handle all edge cases, including old state files without a `mode` field?

### Key decisions that need your eyes (12 min)

**Flow state creation in speckit-specify** (`.claude/skills/speckit-specify/SKILL.md`, [FR-010](spec.md#fr-010))

The flow state is created as a new `SPEX-FLOW:state` section in the specify skill, separate from the ship guard. It only creates flow state when no ship pipeline is active.
- Question: Is the condition `mode = flow OR no file` sufficient to prevent accidentally overwriting a ship state?

**Review artifact split** ([FR-012](spec.md#fr-012) through [FR-015a](spec.md#fr-015a))

All three review skills now produce individual files (REVIEW-SPEC.md, REVIEW-PLAN.md, REVIEW-CODE.md). The ship pipeline's `verify_stage_artifacts()` accepts both old and new formats.
- Question: Should the REVIEWERS.md fallback have an expiration date, or is permanent backward compatibility acceptable?

**Celebration in verification skill** ([FR-019](spec.md#fr-019) through [FR-022](spec.md#fr-022))

The celebration banner, stats computation, and state file removal are added to `verification-before-completion/SKILL.md` as a new step 8.
- Question: Is it appropriate to remove the state file inside the verification skill, or should cleanup be a separate concern?

### Areas where I'm less certain (5 min)

- The `read -r ... < <(jq ... | @tsv)` pattern in the statusline script relies on bash process substitution. If `jq` fails silently (e.g., malformed JSON), the variables will be empty and the script exits 0 (silent degradation). This matches [FR-006](spec.md#fr-006) intent but could mask real issues during development.
- The celebration stats computation (duration, review count, commit count) is specified in the skill's Markdown instructions. Whether the LLM will compute duration correctly from ISO 8601 timestamps depends on its capabilities, not on deterministic code.

### Deviations and risks (5 min)

- No deviations from [plan.md](plan.md) were identified.
- The `.gitignore` update replaces `.spex-ship-phase` with `.spex-state`, but existing projects that already ran `spex-init.sh` will not get the updated pattern automatically (the sentinel check prevents re-appending). This means `.spex-state` files could be accidentally committed in older projects until they re-run init.

---

## Deep Review Report

> Automated multi-perspective code review results. This section summarizes
> what was checked, what was found, and what remains for human review.

**Date:** 2026-04-07 | **Rounds:** 1/3 | **Gate:** PASS

### Review Agents

| Agent | Findings | Status |
|-------|----------|--------|
| Correctness | 5 | completed |
| Architecture & Idioms | 7 | completed |
| Security | 5 | completed |
| Production Readiness | 5 | completed |
| Test Quality | 3 | completed |
| CodeRabbit (external) | 0 | skipped (not invoked) |
| Copilot (external) | 0 | skipped (not installed) |

### Findings Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 9 | 2 | 7 (pre-existing) |
| Minor | 10 | 0 | 10 (pre-existing) |

### What was fixed automatically

Consolidated multiple `jq` process invocations in the status line script into single calls per mode (production-readiness + architecture agents). Refactored repetitive milestone rendering from 4 copy-pasted blocks into a loop over arrays (architecture agent).

### What still needs human attention

All Critical and Important findings were resolved for code introduced by this feature. 7 Important findings remain in pre-existing code (see [review-findings.md](review-findings.md) for details). No further review action needed for this feature, but reviewers may want to address pre-existing issues in a follow-up.

### Recommendation

All findings from new code addressed. Code is ready for human review with no known blockers.
