# Feature Specification: Worktrees Trait

**Feature Branch**: `007-worktrees-trait`
**Created**: 2026-03-19
**Status**: Draft
**Input**: Brainstorm document `brainstorm/worktrees-trait.md`

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Isolated Feature Development After Specify (Priority: P1)

A developer brainstorms and specifies a new feature from the `main` branch. After `speckit.specify` completes, the system automatically creates a git worktree for the feature branch in a sibling directory, restores `main` in the original repo, writes a context handoff file into the worktree, and prints instructions for how to continue working in the worktree. This prevents branch switches from disrupting other Claude Code sessions.

**Why this priority**: This is the core value proposition. Without worktree isolation, every `speckit.specify` disrupts all other sessions sharing the same repo. This story solves the fundamental problem.

**Independent Test**: Can be fully tested by running `speckit.specify` with the worktrees trait enabled, verifying the worktree exists at the expected path, the original repo is back on `main`, and the handoff file contains a summary with pointers.

**Acceptance Scenarios**:

1. **Given** a project with the `worktrees` trait enabled and the repo on `main`, **When** the user completes `speckit.specify` for a new feature, **Then** a git worktree is created at `<base_path>/<branch-name>` with the feature branch checked out
2. **Given** the worktree was just created, **Then** the original repo is switched back to `main` so other sessions are unaffected
3. **Given** the worktree was just created, **Then** a context handoff file exists at `<worktree>/.claude/handoff.md` containing a brief summary of the brainstorm, a pointer to the spec file, and a suggested next step
4. **Given** the worktree was just created, **Then** clear instructions are printed showing the user how to start a new Claude session in the worktree directory

---

### User Story 2 - Worktree Listing (Priority: P2)

A developer working on multiple features needs to see which worktrees exist, which branches they track, and which features they correspond to. They run an `sdd:worktree` command to get an overview of all active worktrees.

**Why this priority**: With multiple features in parallel, discoverability matters. Without a listing, the user must remember or manually inspect directories.

**Independent Test**: Can be tested by creating two worktrees for different features, then running the list command and verifying both appear with correct branch and path information.

**Acceptance Scenarios**:

1. **Given** one or more worktrees exist for the project, **When** the user requests a worktree listing, **Then** the system displays each worktree's path, branch name, and feature name
2. **Given** no worktrees exist, **When** the user requests a listing, **Then** the system reports that no worktrees are active

---

### User Story 3 - Worktree Cleanup After Merge (Priority: P3)

A developer finishes a feature and merges it back to `main`. When they return to the original repo, the system offers to remove the worktree directory for the merged branch. The developer can accept or decline.

**Why this priority**: Without cleanup, stale worktree directories accumulate over time. Offering cleanup at the right moment (after merge) is more natural than requiring periodic manual housekeeping.

**Independent Test**: Can be tested by merging a feature branch, running the cleanup command, and verifying the worktree directory and branch reference are removed.

**Acceptance Scenarios**:

1. **Given** a worktree whose branch has been merged into `main`, **When** the user runs the cleanup command, **Then** the system identifies the merged worktree and offers to remove it
2. **Given** a worktree with unmerged changes, **When** the user runs cleanup, **Then** the system warns that the branch is unmerged and does not remove it unless explicitly confirmed
3. **Given** the user accepts removal, **Then** both the worktree directory and the git worktree reference are removed

---

### Edge Cases

- What happens when a worktree directory already exists at the target path? The system MUST detect this and report an error rather than overwriting.
- What happens when the user runs `speckit.specify` while already in a worktree? The system MUST warn that worktree nesting is not supported and skip worktree creation.
- What happens when `git worktree add` fails (e.g., disk full, permission denied)? The system MUST report the error, leave the original repo on the feature branch (since it cannot cleanly restore), and advise the user to resolve manually.
- What happens when uncommitted changes prevent `git checkout main`? The system MUST abort the checkout, leave the repo on the feature branch, and warn the user to commit or stash their changes before retrying. The worktree is still created successfully in this case.
- What happens when the `worktrees` trait is enabled but the feature branch was not created by `speckit.specify`? The trait only activates as a post-specify step, so manual branch creation is unaffected.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST create a git worktree at `<base_path>/<branch-name>` after `speckit.specify` completes, where `base_path` defaults to `..` (sibling directory)
- **FR-002**: The system MUST switch the original repository back to the `main` branch after creating the worktree. If uncommitted changes prevent the checkout, the system MUST abort, leave the repo on the feature branch, and warn the user to commit or stash first
- **FR-003**: The system MUST write a context handoff file at `<worktree>/.claude/handoff.md` containing: a brief summary of brainstorm decisions (5-10 lines), a pointer to the spec file path, and a suggested next step
- **FR-004**: The system MUST print clear instructions showing the exact command to start a new Claude session in the worktree (e.g., `cd ../<branch-name> && claude`)
- **FR-005**: The system MUST provide a worktree listing capability that shows path, branch, and feature name for all project-related worktrees
- **FR-006**: The system MUST provide a cleanup capability that detects worktrees whose branches are merged and offers removal
- **FR-007**: The system MUST refuse to remove worktrees with unmerged branches unless the user explicitly confirms
- **FR-008**: The system MUST detect and report an error when the target worktree path already exists
- **FR-009**: The system MUST warn and skip worktree creation when already running inside a worktree
- **FR-010**: The worktree base path MUST be configurable via the trait configuration in `.specify/sdd-traits.json`

### Key Entities

- **Trait Configuration**: The `worktrees` entry in `.specify/sdd-traits.json`, containing `enabled` (boolean) and `base_path` (string, default `..`)
- **Context Handoff File**: A gitignored markdown file at `<worktree>/.claude/handoff.md` that bridges context between the brainstorm/specify session and the new worktree session
- **Worktree**: A git worktree directory created at `<base_path>/<branch-name>`, containing a full copy of the working tree on the feature branch

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After `speckit.specify` with the worktrees trait enabled, the original repo is on `main` and a worktree directory exists at the expected path, in under 10 seconds of additional time
- **SC-002**: A developer can start a new Claude session in the worktree and immediately see the spec and handoff context without any manual setup
- **SC-003**: Multiple features can be developed in parallel, each in its own worktree, without any branch conflicts in the original repo
- **SC-004**: Worktree listing shows all active worktrees with correct metadata within 2 seconds
- **SC-005**: Cleanup correctly identifies merged branches and removes only those the user approves

## Clarifications

### Session 2026-03-20

- Q: If uncommitted changes prevent `git checkout main` after worktree creation, what should happen? → A: Abort the checkout, leave repo on feature branch, warn user to commit or stash manually first. The worktree is still created successfully.

## Assumptions

- The project uses git and the `main` branch as the primary integration branch
- The user has sufficient disk space for additional worktree directories
- The `.claude/` directory is gitignored (handoff files are not committed)
- All spec-kit tracked files (constitution, traits config, spec templates) are committed to git and therefore available in worktrees without special handling
- The user starts new Claude sessions via the terminal (not via an IDE integration that might not support directory switching)
