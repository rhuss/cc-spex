# Brainstorm: Deterministic closeout gate for unresolved findings

**Date:** 2026-07-03
**Status:** active
**Issue:** [#9](https://github.com/rhuss/cc-spex/issues/9)

## Problem Framing

The deep review produces findings classified as Critical, Important, Minor, or Notable. The ship pipeline and verify/stamp gates have prompt-level rules saying "do not proceed with unresolved Critical/Important findings." But in autonomous mode (`ask: smart` or `never`), the AI agent can skip these rules because they're just text instructions, not enforced by a script.

The result: a ship pipeline can complete with unresolved Critical findings, which defeats the purpose of the review.

## Decision

Add a deterministic shell script (`spex-closeout-gate.sh`) that reads the deep review report, counts remaining Critical + Important findings, and exits non-zero when any remain. Wire it into the verify/stamp gate as Step 0.

The script follows the same pattern as `spex-ship-state.sh` and `spex-flow-state.sh`: deterministic behavior in bash+jq, not AI-interpreted markdown.

## Key Requirements

1. **Script**: `spex/scripts/spex-closeout-gate.sh` reads `REVIEW-CODE.md` (or a structured findings file) from the feature's spec directory
2. **Parsing**: Extract the findings table from the deep review report, count rows where severity is Critical or Important and status is not "fixed"
3. **Exit codes**: 0 = pass (no unresolved Critical/Important), 1 = fail (unresolved findings exist), with details on stderr
4. **Fail-open default**: If no review report exists, pass (does not force deep review on projects that don't use it)
5. **Fail-closed option**: `SPEX_CLOSEOUT_STRICT=1` env var makes it fail when no review report exists
6. **Integration**: Add as Step 0 of `speckit.spex-gates.verify.md` and `speckit.spex-gates.stamp.md`
7. **Ship pipeline**: The `review-code` stage (Stage 7) already runs deep review. The closeout gate runs at verify/stamp time to catch cases where findings were introduced after review

## Scope

- One new script (~100-150 lines)
- Two command file updates (verify.md, stamp.md) adding Step 0
- Extension manifest update (if the script needs registration)
- Tests following existing `tests/` patterns

## Open Questions

None. The issue author's proposal is well-defined.
