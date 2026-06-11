# Implementation Plan: Guided Smoke Test and Ship Pipeline Safety

**Branch**: `025-guided-smoke-test` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/025-guided-smoke-test/spec.md`

## Summary

Add an interactive `/speckit-spex-smoke-test` command that parses acceptance scenarios from spec.md and walks users through each step, executing commands and waiting for confirmation. Change the ship pipeline to replace the finish stage with the smoke test and always stop before merge/PR. Add a smoke test reminder to verify/stamp.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, `jq` for JSON
**Primary Dependencies**: `specify` CLI
**Storage**: `.specify/.spex-state` JSON file (extended with smoke test fields)
**Testing**: `make release` (plugin integration test)
**Target Platform**: Claude Code (macOS/Linux)
**Project Type**: CLI plugin (spec-kit extension bundle)
**Constraints**: No compiled artifacts, markdown + bash only per constitution

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | New command in existing spex extension, no new extension |
| III. Extension Composability | PASS | Smoke test works independently of other extensions |
| IV. Quality Gates | PASS | Integrates with verify/stamp as informational reminder |
| V. State as Scripts | PASS | State updates via spex-ship-state.sh script |
| Plugin Architecture Constraints | PASS | Markdown + bash only |
| Documentation Maintenance | PASS | README.md and help.md updates included |

No violations.

## Project Structure

### Documentation (this feature)

```text
specs/025-guided-smoke-test/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   ├── spex/
│   │   ├── commands/
│   │   │   ├── speckit.spex.smoke-test.md   # NEW: smoke test command
│   │   │   └── speckit.spex.ship.md         # MODIFY: replace finish with smoke-test stage
│   │   └── extension.yml                    # MODIFY: register new command
│   └── spex-gates/
│       └── commands/
│           └── speckit.spex-gates.verify.md # MODIFY: add smoke test reminder
├── scripts/
│   ├── spex-ship-state.sh                   # MODIFY: add smoke-test state commands
│   └── spex-ship-statusline.sh              # MODIFY: show smoke test indicator
└── docs/
    └── help.md                              # MODIFY: add smoke-test reference
README.md                                    # MODIFY: add smoke-test to commands table
```

**Structure Decision**: One new file (smoke-test command), modifications to 6 existing files, plus docs.

## Implementation Phases

### Phase 1: Smoke Test Command (User Stories 1, 4)

Create the new `/speckit-spex-smoke-test` command as a markdown skill file. This is the core deliverable.

**New file**: `spex/extensions/spex/commands/speckit.spex.smoke-test.md`

The command:
1. Resolves the spec via `check-prerequisites.sh`
2. Parses Given/When/Then scenarios from the spec's "User Scenarios & Testing" section
3. Auto-detects project type and start command (or delegates to `/run` skill)
4. Starts the app as a background process
5. For each scenario: explains the step, executes it, shows result, waits for user confirmation
6. On failure: offers interactive debugging
7. Accepts "skip" to skip a scenario
8. Records results in state file via `spex-ship-state.sh`
9. Cleans up the app process on completion

**State management**: Add `smoke-test-record` command to `spex-ship-state.sh`.

**Key decisions from research**:
- Scenario parsing: regex on bold Given/When/Then keywords in numbered items (R1)
- App lifecycle: background process with SIGTERM cleanup (R3)
- `/run` skill delegation: checked at runtime, not a hard dependency (R2)

### Phase 2: Ship Pipeline Changes (User Story 3)

Modify the ship pipeline to replace finish (stage 8) with smoke-test and stop.

**File modified**: `spex/extensions/spex/commands/speckit.spex.ship.md`

Changes:
- Stage 8 definition: smoke-test replaces finish
- Smoke test always runs interactively (ignores `ask` level)
- After smoke-test, output instructions to run `/speckit-spex-finish` manually
- Update `--start-from` valid stage names: `smoke-test` replaces `finish`
- When no acceptance scenarios exist, still stop with manual finish instruction

**File modified**: `spex/scripts/spex-ship-state.sh`
- Update stage list so advance at index 8 outputs `PIPELINE_COMPLETE`

### Phase 3: Verify Reminder and Statusline (User Story 2)

Add the smoke test reminder to verify and update the statusline.

**File modified**: `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`
- Add check before "Run Tests": if spec has acceptance scenarios and state lacks `smoke_test_completed: true`, show reminder

**File modified**: `spex/scripts/spex-ship-statusline.sh`
- When smoke test results exist in state, show indicator (e.g., "ST ✓" or "ST 2/3")

### Phase 4: Registration and Documentation

Register the new command and update docs.

**File modified**: `spex/extensions/spex/extension.yml` (add smoke-test command entry)
**File modified**: `README.md` (add smoke-test to commands table, update ship pipeline description)
**File modified**: `spex/docs/help.md` (add smoke-test quick reference)

## Dependencies Between Phases

```
Phase 1 (smoke test command) ─── required by ───→ Phase 2 (ship pipeline)
Phase 1 (smoke test command) ─── required by ───→ Phase 3 (verify reminder)
Phase 2 (ship pipeline)      ─── independent ──── Phase 3 (verify reminder)
Phase 4 (docs)               ─── after all ─────→ Phases 1, 2, 3
```

Phase 1 must come first. Phases 2 and 3 are independent but depend on Phase 1. Phase 4 follows all others.
