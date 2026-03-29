# Implementation Plan: Autonomous Full-Cycle Workflow (spex:yolo)

**Branch**: `010-yolo-autonomous-workflow` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/010-yolo-autonomous-workflow/spec.md`

## Summary

Create a new `spex:yolo` skill that autonomously chains the entire spex workflow (specify through verify) with configurable autonomy levels. The skill orchestrates 9 pipeline stages, tracks state via a JSON phase file, and supports three levels of human oversight (cautious, balanced, autopilot) that control when the pipeline pauses for user input versus auto-fixing review findings.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, Python 3 (hooks)
**Primary Dependencies**: `jq` (JSON parsing), `specify` CLI (spec-kit), existing spex skills and speckit commands
**Storage**: JSON state file (`.specify/.spex-yolo-phase`), Markdown artifacts
**Testing**: Manual verification via `make reinstall` + Claude Code session testing
**Target Platform**: Claude Code CLI plugin (macOS/Linux)
**Project Type**: CLI plugin (Markdown/Bash, no compiled artifacts)
**Performance Goals**: N/A (interactive, single-user)
**Constraints**: Must work within a single Claude Code session context window
**Scale/Scope**: Single skill file + optional status line script

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow for this feature |
| II. Overlay Delegation | PASS | Yolo is a skill, not an overlay. No inline discipline logic. |
| III. Trait Composability | PASS | Yolo requires superpowers + deep-review but does not modify them. Other traits remain independent. |
| IV. Quality Gates | PASS | Yolo invokes existing quality gates; does not create new gate mechanisms. |
| V. Naming Discipline | PASS | Uses `spex:yolo` prefix. Branch follows `NNN-feature-name` pattern. |
| VI. Skill Autonomy | PASS | Single-purpose orchestration skill. Delegates to existing skills via `{Skill:}` references. |
| Plugin Architecture | PASS | Skill in `spex/skills/yolo/SKILL.md`. No compiled artifacts. Uses `jq` for JSON. |

**Post-Phase 1 re-check**: All principles still satisfied. The design delegates to existing skills and introduces no new overlay or trait mechanisms.

## Project Structure

### Documentation (this feature)

```text
specs/010-yolo-autonomous-workflow/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── skill-interface.md  # Phase 1 output
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── skills/
│   └── yolo/
│       └── SKILL.md          # Main skill file (pipeline orchestration)
└── scripts/
    └── spex-yolo-statusline.sh  # Optional status line script (reads .spex-yolo-phase)
```

**Structure Decision**: Single skill file is sufficient. The yolo skill is an orchestrator that delegates to existing skills and commands. No new commands, overlays, or hooks are needed. The optional status line script is a standalone Bash script that reads the JSON state file.

## Complexity Tracking

> No constitution violations to justify.
