# Implementation Plan: spex-detach Extension

**Branch**: `029-upstream-contrib-mode` | **Date**: 2026-06-26 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/029-upstream-contrib-mode/spec.md`

## Summary

The `spex-detach` extension enables contributors to use spex's spec-driven workflow when contributing to upstream projects that don't use SDD. It creates a clean PR branch (via squash-onto-base) with all spec artifacts stripped, and optionally archives specs to a project-specs repository. The extension hooks into the existing `spex-finish` command, adding detach-aware behavior when enabled.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Markdown
**Primary Dependencies**: `git`, `jq`, `specify` CLI (spec-kit >=0.5.2)
**Storage**: File-based (git branches, filesystem paths for archive)
**Testing**: `make release` (integration test), manual verification
**Target Platform**: macOS/Linux CLI (Claude Code environment)
**Project Type**: CLI plugin extension (spex extension bundle)
**Performance Goals**: N/A (CLI operations, no latency targets)
**Constraints**: No compiled artifacts; bash + markdown only (constitution constraint)
**Scale/Scope**: Single user, multiple parallel worktrees

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Self-contained extension bundle at `spex/extensions/spex-detach/` with manifest, commands, config |
| III. Extension Composability | PASS | spex-detach hooks into `before_finish`; does not modify other extensions' files or hooks |
| IV. Quality Gates | PASS | Will use existing verification gates |
| V. Naming Discipline | PASS | `spex-detach` prefix, `speckit.spex-detach.*` command naming, feature branch `029-upstream-contrib-mode` |
| VI. Skill Autonomy | PASS | Single purpose: detach spec artifacts at PR time |
| VII. State as Scripts | PASS | Core logic in `spex-detach.sh` shell script, not inline bash in skill markdown |

No violations. No complexity tracking entries needed.

## Project Structure

### Documentation (this feature)

```text
specs/029-upstream-contrib-mode/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── spex-detach-sh.md
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
spex/
├── extensions/
│   └── spex-detach/                          # NEW: Extension bundle
│       ├── extension.yml                     # Extension manifest
│       ├── config-template.yml               # Config template (archive path)
│       └── commands/
│           └── speckit.spex-detach.detach.md  # Manual detach command
├── scripts/
│   └── bash/
│       └── spex-detach.sh                    # NEW: Shell script for git operations
│   └── spex-init.sh                          # MODIFIED: Add spex-detach to install order

spex/extensions/spex/commands/
└── speckit.spex.finish.md                    # MODIFIED: Add detach-aware behavior
```

**Structure Decision**: Extension follows the established bundle pattern. The core git operations (clean branch creation, archiving) live in a shell script per constitution principle VII. The finish command is modified minimally to detect and delegate to the extension.

## Design Decisions

### D1: Integration with finish command

The `spex-detach` extension modifies the finish flow rather than creating a separate finish command. This keeps the UX simple (one `/speckit-spex-finish` command) while the extension's behavior is gated on whether `spex-detach` is installed and enabled.

**Integration points in finish:**
1. After Phase 2 (commit outstanding changes): call `spex-detach.sh detach` to create the clean PR branch
2. After Phase 2: call `spex-detach.sh archive` if archive path is configured
3. Phase 4 (action selection): when detach is active, modify PR options to push the clean `pr/<branch>` branch instead of the feature branch
4. Phase 5 (execute action): push `pr/<branch>` for the upstream PR

**Why modify finish instead of wrapping it:** The constitution allows extensions to hook into lifecycle events. Creating a wrapper would force users to remember a different command and would duplicate verification/cleanup logic.

### D2: Clean PR branch mechanism (squash-onto-base)

```
merge-base = git merge-base <upstream-default> <feature-branch>
diff = git diff <merge-base>..<feature-branch> -- ':!.specify' ':!specs' ':!brainstorm'
apply diff as single commit on new branch pr/<feature-branch>
```

The squash-onto-base approach:
1. Find the merge-base between the feature branch and upstream's default branch
2. Compute the diff, excluding `.specify/`, `specs/`, and `brainstorm/` paths
3. Create branch `pr/<feature-branch-name>` from the merge-base
4. Apply the filtered diff as a single commit

This produces a clean branch where the upstream PR diff shows only code changes, with no trace of spec artifacts in history.

### D3: Extension configuration

The extension uses a config file (`spex-detach-config.yml`) installed to `.specify/extensions/spex-detach/` at init time. This follows the pattern established by `spex-collab` and `spex-deep-review`.

Config fields:
- `archive.path`: Local filesystem path to the project-specs repo (optional)
- `archive.auto_commit`: Whether to auto-commit archived specs (default: true)
- `upstream.default_branch`: Override for upstream's default branch (default: auto-detect from `origin`)
- `detach.strip_paths`: List of paths to strip (default: `.specify`, `specs`, `brainstorm`)

### D4: Archive structure

Archived specs are organized by project and feature:
```
<archive-path>/<project-name>/<feature-name>/
├── .specify/          # Spec-kit config and state
└── specs/<feature>/   # Spec, plan, tasks
```

Project name is derived from the git remote's `owner/repo` (e.g., `opendatahub-io/odh-dashboard`). Feature name is the branch name.

### D5: Extension install order

`spex-detach` has no dependencies on other extensions. It hooks into the core `spex` extension's finish command. Install order position: after `spex-worktrees`, before `spex-deep-review`.

Updated install order:
```bash
local install_order=(spex spex-gates spex-worktrees spex-detach spex-deep-review spex-teams spex-collab)
```
