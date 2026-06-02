# Implementation Plan: Collab Triage Lifecycle

**Branch**: `022-collab-triage-lifecycle` | **Date**: 2026-06-02 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/022-collab-triage-lifecycle/spec.md`

## Summary

Add `triage-spec` and `triage-impl` as recognized workflow phases in the spex collab extension. After PR creation (spec or impl), display a suggest-with-delay message prompting the user to run the triage loop. After spec triage completes, a gate check in the phase-manager compares review comment count against a configurable threshold to recommend same-PR continuation or spec-PR merge with separate impl PR(s). The status line gets a new `T` badge for triage state visibility.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3, Markdown
**Primary Dependencies**: `jq`, `yq`, `gh` CLI, `specify` CLI
**Storage**: JSON state files (`.specify/.spex-state`, `.specify/.pr-triage-state.json`)
**Testing**: Manual integration testing via `make release`
**Target Platform**: Claude Code CLI (macOS/Linux)
**Project Type**: CLI plugin (markdown commands + shell scripts)
**Performance Goals**: N/A (workflow orchestration, not performance-critical)
**Constraints**: No compiled artifacts, bash + jq + markdown only
**Scale/Scope**: 5 files modified, 1 config template updated

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Changes extend existing spex-collab extension commands |
| III. Extension Composability | PASS | Triage phases only activate when spex-collab is enabled; no cross-extension modification |
| IV. Quality Gates | PASS | Adds new gate check (triage threshold) consistent with existing pattern |
| V. Naming Discipline | PASS | Uses existing `speckit.spex-collab.*` command naming |
| VI. Skill Autonomy | PASS | Gate check logic lives in phase-manager (its responsibility), state in flow-state script |
| VII. State as Scripts | PASS | New gate actions added to `spex-flow-state.sh`, not inline bash in markdown |

## Project Structure

### Documentation (this feature)

```text
specs/022-collab-triage-lifecycle/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (from /speckit-tasks)
```

### Source Code (files to modify)

```text
spex/
├── scripts/
│   ├── spex-flow-state.sh           # Add triage-spec/triage-impl gate actions
│   └── spex-ship-statusline.sh      # Add T badge rendering (flow mode only, collab-conditional)
├── extensions/
│   └── spex-collab/
│       ├── config-template.yml      # Add triage.split_threshold and triage.loop_interval
│       └── commands/
│           └── speckit.spex-collab.phase-manager.md  # Add triage gate check after spec triage
```

**Structure Decision**: All changes are additive modifications to existing files. No new files needed beyond spec artifacts.
