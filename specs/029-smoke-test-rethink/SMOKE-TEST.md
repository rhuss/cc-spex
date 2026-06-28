# Smoke Test Report

**Feature**: Focused Interactive Smoke Test
**Date**: 2026-06-28
**Spec**: specs/029-smoke-test-rethink/spec.md
**Result**: 0 passed, 3 skipped, 0 failed (out of 3)

---

## Scenario 1: Run smoke test against spec with `## Smoke Test` section

**Skip reason**: Requires a fresh Claude session to exercise the smoke test command. Running it in the session that wrote the command would be self-testing (violates no-simulation hard gate).

**Manual test instructions**:
1. Start a new Claude session in the cc-spex worktree
2. Run `/speckit-spex-smoke-test`
3. Verify it finds 3 scenarios from the `## Smoke Test` section (not the 12 acceptance scenarios)
4. Verify each scenario is presented for human judgment (no auto-verify)
5. Verify SMOKE-TEST.md is produced after the walkthrough

### Verdict: SKIP

---

## Scenario 2: Run smoke test against spec with no `## Smoke Test` section

**Skip reason**: Requires invoking the command in a fresh session against a spec without the section.

**Manual test instructions**:
1. Start a new Claude session
2. Set `.specify/feature.json` to point to a spec without `## Smoke Test` (e.g., `specs/028-smoke-test-v2`)
3. Run `/speckit-spex-smoke-test`
4. Verify it outputs "No smoke test scenarios defined in spec — skipping" and exits cleanly

### Verdict: SKIP

---

## Scenario 3: Run ship pipeline with `## Smoke Test` section

**Skip reason**: Partially validated by this pipeline run (Stage 8 correctly detected the section and paused for interactive walkthrough). Full validation requires running a complete pipeline in a fresh session.

**Partial evidence**: This ship pipeline run (`/speckit-spex-ship 24-smoke-test-rethink`) reached Stage 8, detected the `## Smoke Test` section via `grep -c '^## Smoke Test$'`, and paused for interactive walkthrough — matching expected behavior per FR-009.

**Manual test instructions**:
1. Run `/speckit-spex-ship` on a feature with a `## Smoke Test` section in a fresh session
2. Verify Stage 8 pauses for interactive walkthrough
3. Walk through scenarios and verify SMOKE-TEST.md is produced
4. Verify the pipeline completes and stops (does not auto-invoke finish)

### Verdict: SKIP
