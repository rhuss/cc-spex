# Implementation Plan: spex-detach Extension

**Branch**: `029-upstream-contrib-mode` | **Date**: 2026-06-28 | **Spec**: specs/029-upstream-contrib-mode/spec.md
**Input**: Feature specification from `/specs/029-upstream-contrib-mode/spec.md`

## Summary

Implement `spex-detach` as a new extension bundle that enables spec-driven development for upstream contributions. At finish time, the extension creates a clean PR branch (`pr/<feature-branch>`) by computing a filtered diff (excluding `.specify/`, `specs/`, `brainstorm/`) against the merge-base with the upstream default branch, applying it as a single squashed commit. The extension optionally archives spec artifacts to a configured project-specs repository. Clean branch creation is integrated directly into the finish command (after Phase 2 commit), while archiving hooks into `before_finish`. All git operations are delegated to `spex-detach.sh` per Constitution VII.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown
**Primary Dependencies**: `specify` CLI (>=0.5.2), `git`, `jq`, `gh` (for PR creation), `yq` (for config parsing)
**Storage**: File-based (`.specify/extensions/spex-detach/`)
**Testing**: `make release` (schema validation + integration test)
**Target Platform**: macOS, Linux
**Project Type**: Claude Code plugin (extension bundle)
**Performance Goals**: N/A (not performance-critical)
**Constraints**: Must compose with existing extensions without modification (Constitution III)
**Scale/Scope**: Single extension bundle (~5 new files), modifications to finish command and init script

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow for this feature |
| II. Extension Architecture | PASS | Self-contained bundle at `spex/extensions/spex-detach/` with manifest, commands, config template |
| III. Extension Composability | PASS | Does not modify other extension files. Finish command modifications are additive (no behavior change when spex-detach absent). Archive uses `before_finish` hook. |
| IV. Quality Gates | PASS | Standard gates apply throughout |
| V. Naming Discipline | PASS | `speckit.spex-detach.*` command naming, `spex-detach` extension ID |
| VI. Skill Autonomy | PASS | Detach command has single purpose; delegates git ops to script |
| VII. State as Scripts | PASS | All git operations in `spex/scripts/bash/spex-detach.sh`, not inline bash |

**Post-Design Re-Check**: Clean branch creation is integrated INTO the finish command rather than as a separate hook because timing requires it to run after Phase 2 (commit outstanding changes). This is additive modification, not extension cross-modification — the finish command already has similar conditional detection for collab and gates extensions.

## Project Structure

### Documentation (this feature)

```text
specs/029-upstream-contrib-mode/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0: decisions and alternatives
├── data-model.md        # Phase 1: entity definitions
├── quickstart.md        # Phase 1: user-facing guide
├── contracts/
│   └── spex-detach-sh.md  # Phase 1: script interface contract
└── tasks.md             # Phase 2 output (via /speckit-tasks)
```

### Source Code (repository root)

```text
spex/extensions/spex-detach/
├── extension.yml                                    # Extension manifest
├── config-template.yml                              # Default config (archive path, upstream branch)
└── commands/
    └── speckit.spex-detach.detach.md                 # Detach command (manual + before_finish hook)

spex/scripts/bash/
└── spex-detach.sh                                   # Shell script: detach, archive, is-enabled, clean-branch-name

spex/scripts/spex-init.sh                            # Modified: add spex-detach opt-in prompt
spex/extensions/spex/commands/speckit.spex.finish.md  # Modified: detach detection + clean branch option
```

**Structure Decision**: Standard extension bundle layout following `spex-collab` pattern. Script at `spex/scripts/bash/spex-detach.sh` per Constitution VII. Finish command modified inline (same pattern as existing collab/gates detection).

### Modified Files

| File | Change |
|------|--------|
| `spex/scripts/spex-init.sh` | Add spex-detach to install order with opt-in prompt |
| `spex/extensions/spex/commands/speckit.spex.finish.md` | Add detach detection after Phase 2, new "Push clean PR branch" option in Phase 4, clean branch verification |
| `README.md` | Extension documentation, commands reference |
| `spex/docs/help.md` | Quick reference for detach commands |

## Complexity Tracking

No constitution violations requiring justification.

## Design Decisions

### D1: Clean branch creation timing

**Decision**: Inline in finish command after Phase 2 (commit), not as a `before_finish` hook.

**Why**: `before_finish` hooks fire before Phase 1 (verification), which is before Phase 2 (commit outstanding changes). Creating the clean branch before all changes are committed would miss uncommitted work. The detach must happen after commit to capture all code changes.

### D2: Archiving as optional `before_finish` hook

**Decision**: The `speckit.spex-detach.detach` command registered as an optional `before_finish` hook handles archiving. The archive operation is safe to run before verification since it copies existing spec artifacts (already on disk) to the project-specs repo.

### D3: Finish command modification scope

**Decision**: Additive modification only. When `spex-detach` is not installed, zero behavior changes. Detection checks for `.specify/extensions/spex-detach` directory existence — same pattern as existing worktree/collab detection in the finish command.

### D4: Extension is opt-in during init

**Decision**: Not installed by default. `spex-init.sh` prompts the user to opt in. Avoids polluting `.specify/extensions.yml` with disabled hooks.

### D5: Script over inline bash

**Decision**: All git operations (merge-base computation, filtered diff, branch creation, archive copy) in `spex-detach.sh` with JSON output. The finish command and detach skill consume this JSON. Per Constitution VII, this prevents the class of bugs where AI skips or varies inline bash.

## Research Summary

Full research in [research.md](research.md). Key decisions:

| Topic | Decision | Rationale |
|-------|----------|-----------|
| Clean branch mechanism | `git diff --binary` + pathspec exclusions + `git apply --index` | Handles adds/mods/deletes/renames/binaries; native git syntax |
| Upstream default detection | Config override > `symbolic-ref` > `remote show` > `main` fallback | Fast local check first, network fallback, config escape hatch |
| Project name derivation | Parse `upstream`/`origin` remote URL to `owner-repo` | Preserves fork vs upstream distinction |
| Idempotency | Delete + recreate `pr/<branch>` on re-run | Simplest reliable approach |

## Data Model Summary

Full model in [data-model.md](data-model.md). Key entities:

- **Config** (`spex-detach-config.yml`): archive.path, archive.auto_commit, upstream.default_branch, detach.strip_paths
- **Clean PR Branch** (`pr/<feature-branch>`): Single squashed commit from merge-base, code only
- **Archive Directory** (`<archive>/<project>/<feature>/`): Copies of `.specify/` and `specs/<feature>/`

## Contract Summary

Full contract in [contracts/spex-detach-sh.md](contracts/spex-detach-sh.md). Script interface:

| Subcommand | Purpose | Exit Codes |
|------------|---------|------------|
| `detach` | Create clean PR branch | 0=success, 1=error, 2=empty diff |
| `archive` | Copy specs to project-specs repo | 0=success, 1=error |
| `is-enabled` | Check extension status | 0=enabled, 1=not |
| `clean-branch-name` | Output `pr/<branch>` name | 0=always |

## Implementation Phasing

### Phase 1-2: Setup + Foundational (T001-T005)
Extension bundle structure, manifest, config template, script skeleton with helpers.

### Phase 3: US1 — Enable Extension (T006-T007)
`is-enabled` and `clean-branch-name` subcommands. Extension installable and detectable.

### Phase 4: US2 — Clean PR Branch (T008-T012) **MVP**
`detach` subcommand, finish command modifications (detection, option, push, verification). Core value delivered.

### Phase 5: US3 — Archive Specs (T013-T014)
`archive` subcommand, detach command skill for manual/hook invocation.

### Phase 6: US4 — Brainstorm Redirection (T015-T016)
Brainstorm aware of spex-detach config, writes to project-specs repo.

### Phase 7: Polish (T017-T021)
Documentation, edge cases, US5 verification, quickstart validation.

Full task breakdown in [tasks.md](tasks.md).
