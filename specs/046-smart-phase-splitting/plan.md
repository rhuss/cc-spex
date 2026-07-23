# Implementation Plan: Smart Phase Splitting

**Branch**: `046-smart-phase-splitting` | **Date**: 2026-07-23 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/046-smart-phase-splitting/spec.md`

## Summary

Make the collab extension's phase-split system size-aware by adding a file-count threshold gate, merging adjacent small phases, and ensuring single-phase mode runs without interruptions. This modifies two existing skill files (phase-split and phase-manager), adds a `phases` section to the collab config template, and updates documentation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown

**Primary Dependencies**: `jq`, `yq`, `specify` CLI, `grep`/`sed` for file path extraction

**Storage**: `.specify/.spex-state` (JSON), `collab-config.yml` (YAML)

**Testing**: `make release` (schema validation + integration test suite)

**Target Platform**: macOS/Linux (Claude Code CLI)

**Project Type**: CLI plugin (spec-kit extension)

**Performance Goals**: N/A (interactive tool, no latency requirements)

**Constraints**: POSIX-compatible bash, no compiled dependencies beyond `jq`/`yq`

**Scale/Scope**: 3 files modified, 1 config template updated, documentation updates

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Changes stay within spex-collab extension |
| III. Extension Composability | PASS | No cross-extension modifications |
| IV. Quality Gates | PASS | Review gates preserved |
| V. Naming Discipline | PASS | No naming changes |
| VI. Skill Autonomy | PASS | Each command retains single purpose |
| VII. State as Scripts | REVIEW | Phase-split adds inline logic for file estimation; consider whether this should be a script. Decision: keep inline since it's read-only estimation logic (not state mutation). State mutations still use spex-ship-state.sh. |

## Project Structure

### Documentation (this feature)

```text
specs/046-smart-phase-splitting/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (speckit-tasks)
```

### Source Code (modified files)

```text
spex/extensions/spex-collab/
├── commands/
│   ├── speckit.spex-collab.phase-split.md    # MODIFY: add threshold gate, file estimation, merge logic
│   └── speckit.spex-collab.phase-manager.md  # MODIFY: add single-phase skip logic
├── config-template.yml                        # MODIFY: add phases.file_threshold
└── extension.yml                              # NO CHANGE (hooks stay registered)

spex/docs/help.md                              # MODIFY: document phases config
README.md                                      # MODIFY: update collab description
```

**Structure Decision**: All changes are modifications to existing files within the spex-collab extension. No new files or directories needed.

## Design Decisions

### D1: File Estimation Approach

**Decision**: Hybrid approach with plan.md parsing and task-count fallback.

**How it works**:
1. Parse plan.md for file path references using grep for patterns like `path/to/file.ext`, backtick-quoted paths, and code block file references
2. Deduplicate extracted paths
3. If fewer than 5 unique paths found, fall back to task-count * 1.5 heuristic
4. The estimate includes all files (production + test)

**Regex pattern for file extraction**:
```bash
# Match patterns like: src/foo/bar.sh, `path/to/file.md`, ./relative/path.yml
grep -oE '[a-zA-Z0-9_./-]+\.[a-zA-Z]{1,5}' "$PLAN_FILE" | \
  grep -v '^\.' | \
  grep '/' | \
  sort -u
```

This catches most file references without requiring structured markup in plan.md.

### D2: Phase Merge Algorithm

**Decision**: Greedy forward merge of adjacent phases.

**Algorithm**:
1. Start with phases parsed from tasks.md (existing detection logic)
2. For each phase, estimate files it touches by checking which plan.md file paths relate to its tasks
3. If a phase touches fewer than 10 files, merge it with the next adjacent phase
4. Continue merging until the combined phase reaches 10+ files or no more adjacent phases exist
5. If merging produces a single phase, treat as single-phase mode (no prompt)

**Why greedy forward**: Simple, preserves logical ordering, and avoids the complexity of optimal bin-packing. The phases already have a natural ordering from tasks.md.

### D3: Single-Phase Detection in phase-manager

**Decision**: phase-manager reads `collab.phase_plan` from `.spex-state`. If the plan contains exactly one phase, skip the inter-implementation invocation. The phase-split output instructions drive when phase-manager runs.

**Mechanism**: The phase-split command already outputs explicit per-phase instructions ("Run /speckit-implement... Then /speckit-spex-collab-phase-manager"). In single-phase mode, phase-split outputs instructions that call phase-manager only once at the end. The phase-manager itself also checks: if `phase_plan` length is 1, it knows it's the final (and only) invocation.

### D4: Threshold Configuration

**Decision**: Add `phases.file_threshold` to collab-config.yml, read with yq, default to 20.

```yaml
phases:
  file_threshold: 20    # minimum estimated files to propose multi-phase split
```

## Complexity Tracking

No constitution violations requiring justification.
