# Implementation Plan: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/015-worktree-post-specify/spec.md`

## Summary

Update the existing worktrees trait to use colon-convention naming (`<repo-name>:<branch-name>`), commit all modified tracked files before branch switching, and ensure trait overlay ordering guarantees worktree creation runs after superpowers review. This is primarily a modification of the existing `spex:worktree` skill and its overlay, not a greenfield implementation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown, Python 3 (hooks)
**Primary Dependencies**: `jq` (JSON parsing), `specify` CLI (spec-kit), `git` (worktree management)
**Storage**: File-based (`.specify/spex-traits.json` for config, git for state)
**Testing**: Manual integration testing via `make release` (schema validation + full plugin install test)
**Target Platform**: macOS/Linux (Claude Code CLI environment)
**Project Type**: CLI plugin (Claude Code spex plugin)
**Performance Goals**: SC-001: worktree creation within 15 seconds of specify completing
**Constraints**: No compiled artifacts, Markdown + Bash only, overlay files <= 30 lines
**Scale/Scope**: Single-user local development workflow

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | **Pass** | Cross-cutting feature, following SDD workflow |
| II. Overlay Delegation | **Pass** | Overlay delegates to `{Skill: spex:worktree}`, stays under 30 lines |
| III. Trait Composability | **Pass** | Worktrees trait is independent, uses own overlay directory |
| IV. Quality Gates | **Pass** | Superpowers overlay runs review before worktree creation |
| V. Naming Discipline | **Pass** | Branch follows `NNN-feature-name`; uses `specify` CLI correctly |
| VI. Skill Autonomy | **Pass** | Worktree skill has single purpose, delegates nothing |

No violations. Complexity Tracking table not needed.

## Project Structure

### Documentation (this feature)

```text
specs/015-worktree-post-specify/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── tasks.md             # Phase 2 output (via /speckit.tasks)
└── checklists/          # Spec quality checklist
```

### Source Code (repository root)

```text
spex/
├── skills/
│   └── worktree/
│       └── SKILL.md                          # Main skill (update: colon naming, commit scope)
├── overlays/
│   └── worktrees/
│       └── skills/
│           ├── speckit-specify/
│           │   └── SKILL.append.md           # Post-specify overlay (update: clarify ordering)
│           ├── speckit-plan/
│           │   └── SKILL.append.md           # Context note (no changes needed)
│           └── speckit-implement/
│               └── SKILL.append.md           # Context note (no changes needed)
├── scripts/
│   └── spex-traits.sh                        # Trait manager (verify ordering behavior)
└── commands/
    └── worktree.md                           # Command dispatcher (no changes needed)
```

**Structure Decision**: This feature modifies existing files in the established `spex/` plugin structure. No new directories or structural changes needed.
