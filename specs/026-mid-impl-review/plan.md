# Implementation Plan: Mid-Implementation Review Checkpoints

**Branch**: `026-mid-impl-review` | **Date**: 2026-06-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/026-mid-impl-review/spec.md`

## Summary

Add two correctness-focused review checkpoints during ship pipeline implementation (at 1/3 and 2/3 of task completion) and per-agent statistics tracking with leaderboard for all deep review runs. Checkpoints catch drift early; statistics reveal which agents and layers deliver value.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, `jq` for JSON
**Primary Dependencies**: `specify` CLI, `yq` for config reading
**Storage**: `.specify/.spex-state` JSON file (extended with checkpoint counts)
**Testing**: `make release` (plugin integration test)
**Target Platform**: Claude Code (macOS/Linux)
**Project Type**: CLI plugin (spec-kit extension bundle)
**Constraints**: No compiled artifacts, markdown + bash only per constitution

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Changes to existing commands, no new extension |
| III. Extension Composability | PASS | Checkpoints gated on deep-review extension; statistics added to deep-review command |
| IV. Quality Gates | PASS | Checkpoints are quality gates within implementation |
| V. State as Scripts | PASS | Checkpoint counts stored via state script |
| Plugin Architecture Constraints | PASS | Markdown + bash only |
| Documentation Maintenance | PASS | README.md and help.md updates included |

No violations.

## Project Structure

### Source Code (repository root)

```text
spex/
├── extensions/
│   ├── spex/
│   │   └── commands/
│   │       └── speckit.spex.ship.md          # MODIFY: add checkpoint instructions to implement subagent prompt
│   └── spex-deep-review/
│       └── commands/
│           └── speckit.spex-deep-review.run.md # MODIFY: add statistics reporting
├── scripts/
│   └── spex-ship-state.sh                    # MODIFY: add checkpoint-record command
└── docs/
    └── help.md                               # MODIFY: add checkpoint config reference
README.md                                     # MODIFY: add checkpoint description
```

**Structure Decision**: All changes modify existing files. No new files.

## Implementation Phases

### Phase 1: Checkpoint State Management (US1 infrastructure)

Add checkpoint state recording to the state script.

**File modified**: `spex/scripts/spex-ship-state.sh`
- Add `checkpoint-record` command that accepts `--checkpoint <1|2> --findings <N> --fixed <N>` and writes `checkpoint_N_findings` and `checkpoint_N_fixed` to the state file

### Phase 2: Mid-Implementation Checkpoints (US1)

Add checkpoint instructions to the ship pipeline's implement subagent prompt.

**File modified**: `spex/extensions/spex/commands/speckit.spex.ship.md`

The ship pipeline (Stage 6) already reads the task count and builds a subagent prompt. Changes:
1. Before spawning the implement subagent, calculate checkpoint positions: `cp1 = round(total_tasks * 0.33)`, `cp2 = round(total_tasks * 0.67)`
2. Check if deep-review extension is enabled and `implement.review_checkpoints` config is true
3. If both true and total_tasks >= 3, add checkpoint instructions to the subagent prompt telling it to pause after task cp1 and cp2, spawn a fresh-context Agent for correctness review, fix findings (max 2 attempts), and record results via `spex-ship-state.sh checkpoint-record`

### Phase 3: Deep Review Statistics (US2)

Add per-agent statistics reporting to the deep review command.

**File modified**: `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

The deep review already dispatches 5 agents and collects findings. Changes:
1. After all agents complete and the fix loop finishes, format a statistics table from the collected per-agent data
2. Output the agent leaderboard: table with agent name, found, fixed, remaining columns, plus total row
3. Highlight the MVP agent (most findings) or "Clean review" if all agents found 0
4. This runs in all modes (ship and regular flow)

### Phase 4: Layer Comparison (US3)

Add layer comparison to the deep review statistics when checkpoint data exists.

**File modified**: `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

After the agent leaderboard:
1. Check the state file for `checkpoint_1_findings` and `checkpoint_2_findings`
2. If present (meaning checkpoints ran in this pipeline), compute "unique" counts by comparing checkpoint finding locations against final deep review findings
3. Output the layer comparison table
4. If no checkpoint data in state file, skip the layer comparison (regular flow)

### Phase 5: Documentation

Update docs to cover checkpoints and statistics.

**File modified**: `README.md` (add checkpoint description to ship pipeline section)
**File modified**: `spex/docs/help.md` (add `implement.review_checkpoints` config key)

## Dependencies Between Phases

```
Phase 1 (state management) ─── required by ───→ Phase 2 (checkpoints)
Phase 2 (checkpoints)      ─── independent ──── Phase 3 (statistics)
Phase 3 (statistics)       ─── required by ───→ Phase 4 (layer comparison)
Phase 5 (docs)             ─── after all ─────→ Phases 1-4
```

Phase 1 must come first (checkpoints need state recording). Phases 2 and 3 are independent of each other. Phase 4 depends on Phase 3. Phase 5 follows all others.
