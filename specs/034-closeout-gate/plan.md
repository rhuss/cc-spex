# Implementation Plan: Deterministic closeout gate

**Branch**: `034-closeout-gate` | **Date**: 2026-07-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/034-closeout-gate/spec.md`

## Summary

Add a shell script (`spex-closeout-gate.sh`) that parses the REVIEW-CODE.md severity summary table and exits non-zero when unresolved Critical or Important findings remain. Wire it into the verify and stamp gate commands as Step 0, providing deterministic enforcement that the autonomous pipeline cannot bypass.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), uses `grep` and `awk` for markdown table parsing
**Primary Dependencies**: None beyond standard Unix tools (grep, awk, sed)
**Storage**: N/A (reads existing REVIEW-CODE.md, produces no new files)
**Testing**: Shell-based tests following existing `tests/` patterns
**Target Platform**: Claude Code (AI agent harness), macOS + Linux
**Project Type**: Plugin (AI agent extension system)
**Performance Goals**: < 1 second execution
**Constraints**: Must work with bash 3.2 (macOS built-in)

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Script in `spex/scripts/`, commands in `spex-gates/commands/` |
| III. Extension Composability | PASS | Gate is independent, does not modify other extensions |
| IV. Quality Gates | PASS | This IS a quality gate enhancement |
| V. Naming Discipline | PASS | `spex-closeout-gate.sh` follows existing naming |
| VI. Skill Autonomy | PASS | Script is self-contained with clear single purpose |
| VII. State as Scripts | PASS | Deterministic script, not AI-interpreted inline bash |
| Plugin root detection | PASS | Commands reference script via `$PLUGIN_ROOT` |

No violations.

## Project Structure

### Documentation (this feature)

```text
specs/034-closeout-gate/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
spex/
├── scripts/
│   └── spex-closeout-gate.sh    # NEW: closeout gate script
└── extensions/
    └── spex-gates/
        └── commands/
            └── speckit.spex-gates.verify.md   # MODIFIED: add Step 0
```

Note: `speckit.spex-gates.stamp.md` is NOT modified. Stamp delegates entirely to verify, so it inherits the closeout gate Step 0 automatically.

## Research

### Severity Summary Table Format

From existing REVIEW-CODE.md files, the table format is:

```markdown
| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 0 | 0 | 0 |
| Minor | 1 | - | 1 |
```

**Parsing strategy**: Use `grep` to find rows starting with `| Critical` or `| Important`, then `awk` to extract the 4th column (Remaining). No `jq` needed since input is markdown.

### Script Interface

Following existing spex script patterns:

```
Usage: spex-closeout-gate.sh <spec-dir>

Arguments:
  spec-dir    Path to the feature spec directory

Environment:
  SPEX_CLOSEOUT_STRICT   Set to "1" to fail when no review report exists

Exit codes:
  0   Pass (no unresolved Critical/Important, or no report in fail-open mode)
  1   Fail (unresolved Critical/Important findings)
  2   Usage error

Output (stdout):
  CLOSEOUT_PASS           Gate passes
  CLOSEOUT_FAIL critical=N important=M   Gate fails with counts
  CLOSEOUT_SKIP           No report exists (fail-open)
  CLOSEOUT_STRICT_FAIL    No report in strict mode
```

### Integration Points

The verify and stamp commands both need a new Step 0 that:
1. Resolves the spec directory
2. Runs `$PLUGIN_ROOT/scripts/spex-closeout-gate.sh "$SPEC_DIR"`
3. If exit code is non-zero, stops and reports the failure
4. If exit code is 0, proceeds to existing verification flow

## Verification

```bash
# Full integration test
make release
```
