# Feature Specification: Post-Specify Worktree Creation

**Feature Branch**: `015-worktree-post-specify`
**Created**: 2026-04-06
**Status**: Draft
**Input**: Brainstorm session on worktree creation timing and Approach B design
**Supersedes**: 007-worktrees-trait (worktree creation flow); listing and cleanup behaviors are carried forward

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Worktree After Specify (Priority: P1)

A developer brainstorms a feature on `main`, then runs `/speckit.specify`. After the spec is written, validated, and committed to the feature branch, the worktrees trait automatically creates a git worktree for the feature branch in a sibling directory, restores `main` in the original repo, and prints instructions for starting a new Claude session in the worktree. The developer's other Claude sessions on `main` experience only a brief, non-disruptive branch switch.

**Why this priority**: This is the core workflow. Without it, `speckit.specify` leaves the original repo on the feature branch, disrupting other sessions and requiring manual worktree setup.

**Independent Test**: Run `speckit.specify` with the worktrees trait enabled. Verify: (1) worktree exists at expected sibling path, (2) original repo is back on `main`, (3) spec files are committed on the feature branch, (4) switch instructions are printed.

**Acceptance Scenarios**:

1. **Given** a project with the `worktrees` trait enabled and the repo on `main`, **When** `speckit.specify` completes successfully, **Then** spec files are committed on the feature branch before any branch switch occurs
2. **Given** spec files are committed, **When** the trait restores `main`, **Then** `git checkout main` succeeds because the feature branch (not main) was checked out, so main is free
3. **Given** main is restored, **When** the trait creates the worktree, **Then** `git worktree add <base_path>/<repo-name>:<branch-name> <branch-name>` succeeds because the feature branch is no longer checked out in the original repo
4. **Given** the worktree is created, **Then** instructions are printed showing the exact `cd` and `claude` commands to start a new session

---

### User Story 2 - Worktree Session Bootstrap (Priority: P2)

A developer starts a new Claude session in the worktree directory. The spex initialization hook detects this is a fresh session, runs `spex:init` to regenerate trait-applied skills, and the developer can immediately proceed with `/speckit.plan` or `/speckit.implement`. All spec files, templates, and configuration are available because they are tracked in git.

**Why this priority**: Without automatic bootstrap, the developer would need to manually run init commands and wonder why skills are missing. The worktree session must be self-sufficient from the start.

**Independent Test**: Create a worktree for a feature branch, start a Claude session there. Verify: (1) `spex:init` runs automatically via the existing hook, (2) `.claude/skills/` are regenerated, (3) spec files in `specs/<branch-name>/` are accessible, (4) `.specify/` configuration and scripts are present.

**Acceptance Scenarios**:

1. **Given** a new Claude session in a worktree directory, **When** the session starts, **Then** the existing `spex-initialized: false` sentinel triggers `spex:init` automatically
2. **Given** `spex:init` has completed, **Then** all speckit commands and trait-applied skills are available
3. **Given** the worktree was created from a feature branch, **Then** all tracked files (`.specify/`, `.claude/commands/`, spec files) are present without manual copying

---

### User Story 3 - Worktree Listing (Priority: P3)

A developer working on multiple features needs to see which worktrees exist. They run `/spex:worktree list` to get an overview of all active worktrees with their paths, branches, and feature names.

**Why this priority**: With multiple parallel features, discoverability prevents confusion about where each feature lives.

**Independent Test**: Create two worktrees for different features, run the list command, verify both appear with correct information.

**Acceptance Scenarios**:

1. **Given** one or more feature worktrees exist, **When** the user requests a listing, **Then** the system displays each worktree's path, branch name, and feature name
2. **Given** no feature worktrees exist, **When** the user requests a listing, **Then** the system reports no active worktrees

---

### User Story 4 - Worktree Cleanup (Priority: P4)

A developer finishes a feature and merges it to `main`. They run `/spex:worktree cleanup` to remove stale worktree directories for merged branches.

**Why this priority**: Prevents worktree directory accumulation, but is a housekeeping concern rather than a workflow blocker.

**Independent Test**: Merge a feature branch, run cleanup, verify the worktree directory and git reference are removed.

**Acceptance Scenarios**:

1. **Given** a worktree whose branch is merged into `main`, **When** cleanup runs, **Then** the system offers to remove it
2. **Given** a worktree with unmerged changes, **When** cleanup runs, **Then** the system warns and skips unless explicitly confirmed
3. **Given** the user accepts removal, **Then** both the worktree directory and git worktree reference are removed

---

### Edge Cases

- What happens when the target worktree path already exists? The system MUST detect this and report an error without overwriting. The original repo remains on `main` (since the error occurs after main is restored).
- What happens when the user runs `speckit.specify` while already inside a worktree? The system MUST detect this (`.git` is a file, not a directory) and skip worktree creation, allowing specify to proceed normally on the existing branch.
- What happens when `git checkout main` fails due to uncommitted changes? The system MUST report the error, leave the repo on the feature branch, skip worktree creation, and advise the user to commit or stash changes.
- What happens when `git worktree add` fails (disk full, permissions)? The system MUST report the error clearly. The original repo is already back on `main`, so no recovery is needed. The feature branch still exists and can be used manually.
- What happens when the `worktrees` trait is disabled? The overlay is not applied, so specify behaves exactly as it does today with no worktree creation.
- What happens when no spec files were created (e.g., specify was aborted)? The overlay MUST check that spec files exist before attempting to commit and create a worktree. If no spec files exist, skip silently.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: After `speckit.specify` completes, the system MUST commit all staged and unstaged tracked file changes (spec files, `.specify/` config, and any other modified tracked files) to the feature branch before any branch switch
- **FR-002**: After committing, the system MUST run `git checkout main` to restore the original repo to `main`
- **FR-003**: After restoring main, the system MUST create a worktree at `<base_path>/<repo-name>:<branch-name>` using `git worktree add`, where `<repo-name>` is the basename of the main repository directory
- **FR-004**: The system MUST print clear instructions showing the exact command to start a new Claude session in the worktree (e.g., `cd ../cc-spex:<branch-name> && claude`)
- **FR-005**: The system MUST detect when running inside a worktree (`.git` is a file) and skip worktree creation
- **FR-006**: The system MUST detect and report an error when the target worktree path (`<base_path>/<repo-name>:<branch-name>`) already exists
- **FR-007**: The system MUST provide a listing capability showing path, branch, and feature name for all feature worktrees (branches matching `NNN-*`)
- **FR-008**: The system MUST provide a cleanup capability that detects merged worktrees and offers removal with confirmation
- **FR-009**: The system MUST refuse to remove worktrees with unmerged branches unless explicitly confirmed
- **FR-010**: The worktree base path MUST be configurable via `worktrees_config.base_path` in `.specify/spex-traits.json` (default: `..`)
- **FR-011**: The system MUST NOT create any handoff files. The spec file committed to the feature branch serves as the sole context for the worktree session
- **FR-012**: Worktree sessions MUST be self-bootstrapping via the existing `spex:init` auto-trigger mechanism

### Key Entities

- **Trait Configuration**: The `worktrees` entry in `.specify/spex-traits.json` with `enabled` (boolean) and `worktrees_config.base_path` (string, default `..`)
- **Overlay**: The `SKILL.append.md` file in `spex/overlays/worktrees/skills/speckit-specify/` that injects the post-specify worktree creation steps
- **Worktree**: A git worktree directory at `<base_path>/<repo-name>:<branch-name>` (e.g., `../cc-spex:015-feature`) containing the full working tree on the feature branch

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After `speckit.specify` with the worktrees trait enabled, the original repo is on `main` and a worktree exists at the expected path within 15 seconds of specify completing
- **SC-002**: A developer can start a new Claude session in the worktree and run `/speckit.plan` without any manual setup steps beyond `spex:init` (which auto-triggers)
- **SC-003**: Multiple features can be developed in parallel, each in its own worktree, with no branch conflicts in the original repo
- **SC-004**: The branch switch sequence (specify creates branch, commit, checkout main, worktree add) completes without "branch already checked out" errors because each step frees the previous branch before the next needs it
- **SC-005**: All tracked project files (`.specify/`, `.claude/commands/`, spec files) are available in the worktree without manual copying

## Clarifications

### Session 2026-04-06

- Q: Should worktree directories use `<base_path>/<branch-name>` or `<base_path>/<repo-name>:<branch-name>` naming? → A: Colon convention (`<repo-name>:<branch-name>`), matching existing worktree naming pattern
- Q: Should the pre-switch commit include only `specs/<branch>/` or all modified tracked files? → A: All modified tracked files, ensuring `git checkout main` succeeds cleanly
- Q: Must worktree creation happen after superpowers review, and is ordering guaranteed? → A: Yes, worktree creation after review; trait ordering in `spex-traits.json` determines overlay append order (superpowers before worktrees)

## Assumptions

- The project uses git and `main` as the primary integration branch
- The user has sufficient disk space for sibling worktree directories
- All `.specify/` files (scripts, templates, traits config) are committed to git and available in worktrees
- `.claude/commands/` is committed to git (worktrees inherit commands)
- `.claude/skills/` is gitignored and regenerated per session by `spex:init` + trait overlay application
- The existing `spex-initialized: false` sentinel in the session hook triggers `spex:init` in new worktree sessions
- Trait overlays are appended in the order traits appear in `spex-traits.json`, ensuring superpowers review runs before worktree creation
- `create-new-feature.sh` is the upstream spec-kit version (or updated from it)
- After worktree creation, spec files exist only on the feature branch. The original repo on `main` will not contain the spec directory
