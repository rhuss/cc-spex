# Feature Specification: Worktree CWD Persistence

**Feature Branch**: `032-worktree-cwd-persistence`
**Created**: 2026-06-30
**Status**: Draft
**Input**: Brainstorm 27 - Worktree CWD Persistence

## User Scenarios & Testing

### User Story 1 - Worktrees Created Inside Project Boundary (Priority: P1)

As a developer running the ship pipeline with the spex-worktrees extension, worktrees are created inside `.claude/worktrees/` so that the shell CWD persists reliably throughout the pipeline.

**Why this priority**: This is the core fix. Without it, every worktree pipeline session suffers CWD resets after subagent returns, causing state file reads, git commands, and advance calls to operate on the wrong directory.

**Independent Test**: Run `/speckit-spex-ship` on a feature with spex-worktrees enabled. After the implement stage (subagent), verify CWD is still inside the worktree without any manual recovery.

**Acceptance Scenarios**:

1. **Given** the spex-worktrees extension is enabled with default config, **When** a worktree is created after specify, **Then** it is located at `.claude/worktrees/<branch-name>` inside the project directory
2. **Given** a worktree exists at `.claude/worktrees/<branch-name>`, **When** a subagent returns during the ship pipeline, **Then** the shell CWD remains in the worktree (no "Shell cwd was reset" message)
3. **Given** `.claude/worktrees/` does not exist, **When** a worktree is created, **Then** the directory is created automatically
4. **Given** an existing worktree-config.yml with `base_path: ".."`, **When** the user updates to the new version, **Then** the old config is respected (no forced migration)

---

### User Story 2 - Simplified Worktree Path Computation (Priority: P1)

As a developer, the worktree path no longer includes the repo name prefix since worktrees are inside the project. The path is simply `.claude/worktrees/<branch-name>`.

**Why this priority**: The old path format `repo-name@branch-name` was needed to disambiguate sibling worktrees from different repos. Inside `.claude/worktrees/`, the branch name alone is sufficient.

**Independent Test**: Create a worktree via the worktrees extension. Verify the path is `.claude/worktrees/<branch-name>`, not `.claude/worktrees/repo-name@branch-name`.

**Acceptance Scenarios**:

1. **Given** default worktree config, **When** a worktree is created for branch `032-feature`, **Then** the worktree path is `.claude/worktrees/032-feature`
2. **Given** a custom `base_path` in worktree-config.yml (e.g., `..`), **When** a worktree is created, **Then** the old `repo-name@branch-name` format is used (backward compatible)

---

### User Story 3 - CWD Recovery Script Simplified (Priority: P2)

As a developer, the `spex-worktree-cwd.sh` recovery script is simplified since worktrees inside the project boundary should not trigger CWD resets.

**Why this priority**: The recovery script was created as a workaround for sibling worktrees. With worktrees inside the project, the script becomes a safety net rather than a primary mechanism.

**Independent Test**: Run the recovery script from inside a `.claude/worktrees/` worktree. Verify it returns no output (CWD is already correct).

**Acceptance Scenarios**:

1. **Given** CWD is inside `.claude/worktrees/<branch>`, **When** the recovery script runs, **Then** it outputs nothing (no recovery needed)
2. **Given** CWD was reset to the project root but `SHIP_STATE_FILE` points to a worktree state file, **When** the recovery script runs, **Then** it outputs the worktree path for `cd`

---

### User Story 4 - Documentation Updated (Priority: P2)

As a new user, the README and help docs accurately describe where worktrees are created.

**Why this priority**: Users need to know where their worktrees live for manual operations (listing, cleaning up, debugging).

**Independent Test**: Read the README worktree section and verify it describes `.claude/worktrees/` as the default location.

**Acceptance Scenarios**:

1. **Given** the README exists, **When** a user reads the worktree documentation, **Then** it describes `.claude/worktrees/` as the default worktree location
2. **Given** the help docs exist, **When** a user reads the spex-worktrees command help, **Then** it mentions `.claude/worktrees/` as the default

---

### Edge Cases

- What if `.claude/` is not gitignored? (The init script ensures `.claude/` is in `.gitignore`; worktrees inside it are invisible to git)
- What if the user has a custom `base_path` pointing to an external directory? (Custom config is respected; the new default only applies when no config override exists)
- What if a worktree already exists at the target path from a previous failed run? (Existing behavior: error with "Target path already exists" message)
- What if the project root is on a filesystem that doesn't support nested git worktrees? (Git worktrees work on all filesystems that support symlinks; `.claude/worktrees/` is just a regular directory)

## Requirements

### Functional Requirements

- **FR-001**: The default `base_path` in worktree-config.yml MUST be `.claude/worktrees` instead of `..`
- **FR-002**: The worktree manage command MUST use `.claude/worktrees` as the default when no config override exists
- **FR-003**: Worktree paths inside `.claude/worktrees/` MUST use `<branch-name>` only (no repo name prefix)
- **FR-004**: Worktree paths with custom `base_path` (outside project) MUST continue using `<repo-name>@<branch-name>` format
- **FR-005**: The `.claude/worktrees/` directory MUST be created automatically when the first worktree is created
- **FR-006**: The ship pipeline's worktree detection MUST look for worktrees inside `.claude/worktrees/` by default
- **FR-007**: The `spex-worktree-cwd.sh` recovery script MUST handle both inside-project and outside-project worktrees
- **FR-008**: The README MUST document `.claude/worktrees/` as the default worktree location
- **FR-009**: The help docs MUST reference `.claude/worktrees/` for the worktrees extension

## Success Criteria

### Measurable Outcomes

- **SC-001**: Ship pipeline with worktrees completes all 8 stages without any "Shell cwd was reset" messages
- **SC-002**: Worktree CWD persists across all 4 subagent stages (review-spec, review-plan, implement, review-code) without recovery
- **SC-003**: Existing projects with custom `base_path: ".."` continue to work without changes

## Smoke Test

1. Run `/speckit-spex-ship` with spex-worktrees enabled, verify the worktree is created at `.claude/worktrees/<branch>` and CWD persists through the pipeline
2. Check that `git worktree list` shows the worktree inside the project directory
3. After the pipeline completes, verify the post-pipeline completion prompt runs from the worktree (not the main repo)

## Assumptions

- `.claude/` is already gitignored by the spex init script (verified in `configure_gitignore`)
- The worktree config template is at `spex/extensions/spex-worktrees/config-template.yml`
- The worktree manage command is at `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md`
- Git worktrees work correctly when nested inside the project directory
- The `EnterWorktree` Claude Code tool is not used directly (spex uses `git worktree add` for portability across AI agents)

## Out of Scope

- Automatic migration of existing sibling worktrees to `.claude/worktrees/`
- Using Claude Code's `EnterWorktree` tool instead of `git worktree add`
- Worktree nesting (creating a worktree inside another worktree)
- Worktree cleanup automation beyond what already exists

## Dependencies

- `spex/extensions/spex-worktrees/config-template.yml` (config default)
- `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` (path computation)
- `spex/extensions/spex/commands/speckit.spex.ship.md` (worktree detection in Stage 0)
- `spex/scripts/spex-worktree-cwd.sh` (CWD recovery)
- `README.md` (worktree documentation)
- `spex/docs/help.md` (worktree help)
