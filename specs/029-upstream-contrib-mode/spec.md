# Feature Specification: spex-detach Extension

**Feature Branch**: `029-upstream-contrib-mode`
**Created**: 2026-06-24
**Status**: Draft
**Input**: Brainstorm #23 (Dual-Repo Spec Workflow)

**Extension**: `spex-detach` - Detach spec artifacts at PR time for
contributing to projects that don't use spec-driven development.

## User Scenarios & Testing

### User Story 1 - Enable the spex-detach extension (Priority: P1)

A contributor forks an upstream project that does not use SDD. They want
to use spex's spec-driven workflow to organize their contribution, but
upstream PRs must contain only code changes with no spec artifacts.

The contributor runs `specify init` and enables the `spex-detach`
extension via interactive prompt. This configures the project so that
spec artifacts are committed to the fork's feature branch during
development but detached (stripped) when creating a PR.

**Why this priority**: Without this initialization, none of the other
stories function. This is the foundation of the feature.

**Independent Test**: Run `specify init`, enable `spex-detach` when
prompted, verify `.specify/init-options.json` records the extension
as enabled, and confirm spec-kit commands work normally in the
initialized directory.

**Acceptance Scenarios**:

1. **Given** a code repository without `.specify/`, **When** the
   contributor runs `specify init` and enables `spex-detach`, **Then**
   `.specify/init-options.json` records the extension as enabled.

2. **Given** `spex-detach` is enabled, **When** the contributor runs
   spec-kit commands (`/speckit-specify`, `/speckit-plan`, etc.),
   **Then** all commands work identically to the default mode during
   the specify/plan/implement phases.

3. **Given** a code repository already initialized without
   `spex-detach`, **When** the contributor re-runs init and enables it,
   **Then** the existing `.specify/` is updated without losing current
   configuration.

---

### User Story 2 - Create clean PR branch at finish time (Priority: P1)

After completing implementation in a worktree, the contributor finishes
the feature. The finish command creates a clean PR branch from the
feature branch with all spec directories removed, leaving only code
changes suitable for an upstream PR.

**Why this priority**: This is the core value proposition. Without
clean PR branches, the contributor cannot submit PRs to upstream
projects that don't use SDD.

**Independent Test**: Initialize a project with `spex-detach` enabled, commit
spec and code changes to a feature branch, run `spex-finish`, verify
a clean PR branch exists with no `.specify/`, `specs/`, or
`brainstorm/` directories.

**Acceptance Scenarios**:

1. **Given** a feature branch with both spec artifacts (`.specify/`,
   `specs/`) and code changes, **When** the contributor runs
   `spex-finish`, **Then** a new PR branch named
   `pr/<feature-branch-name>` is created containing only code changes.

2. **Given** the clean PR branch is created, **When** inspecting
   its contents, **Then** no `.specify/`, `specs/`, or `brainstorm/`
   directories exist in the branch.

3. **Given** the clean PR branch is created, **When** the original
   feature branch is inspected, **Then** it still contains all spec
   artifacts intact.

4. **Given** the upstream PR needs revisions, **When** the contributor
   makes changes on the feature branch and re-runs finish, **Then**
   the clean PR branch is regenerated with updated code changes.

---

### User Story 3 - Archive specs to project-specs repo (Priority: P2)

At finish time, spec artifacts are archived to a configured
project-specs repository. This provides durable storage for spec
history across all upstream contributions.

**Why this priority**: Archival prevents loss of design context when
worktrees are deleted. Important but not blocking for the core
PR workflow.

**Independent Test**: Configure an archive target during init, finish
a feature, verify spec artifacts appear in the project-specs repo
under the correct project/feature directory structure.

**Acceptance Scenarios**:

1. **Given** `spex-detach` is enabled and an archive path is configured,
   **When** the contributor runs `spex-finish`, **Then** spec artifacts
   are copied to the archive path organized by project and feature name.

2. **Given** the archive path does not exist, **When** `spex-finish`
   runs, **Then** the archive directory structure is created
   automatically.

3. **Given** specs were previously archived for the same feature,
   **When** `spex-finish` runs again, **Then** the archived specs
   are updated (not duplicated).

---

### User Story 4 - Brainstorm documents stay in project-specs repo (Priority: P2)

Brainstorm documents are always created and maintained in the
project-specs repo, not in code worktrees. When the contributor
transitions from brainstorming to specification, the brainstorm
document is available as context.

**Why this priority**: Brainstorms are pre-specification thinking
that spans features. They belong in a durable location, not tied
to a code branch lifecycle.

**Independent Test**: Run brainstorming in the project-specs repo
context, verify brainstorm documents are not created in the code
worktree, verify the brainstorm content is available as context when
running `/speckit-specify`.

**Acceptance Scenarios**:

1. **Given** the contributor is brainstorming a feature for an upstream
   project, **When** the brainstorm document is written, **Then** it
   is saved to the project-specs repo's `brainstorm/` directory.

2. **Given** a brainstorm document exists in the project-specs repo,
   **When** the contributor runs `/speckit-specify` in a code worktree
   with the brainstorm path as argument (e.g.,
   `/speckit-specify --brainstorm /path/to/brainstorm.md`), **Then**
   the brainstorm content is used as context for the specification.

---

### User Story 5 - Parallel worktrees with independent state (Priority: P1)

The contributor works on multiple features in parallel, each in its
own git worktree with its own Claude Code session. Each worktree has
independent `.specify/` state, so parallel sessions do not interfere
with each other.

**Why this priority**: Without independent state, parallel feature
work causes state collisions and is unusable.

**Independent Test**: Create two worktrees for different features,
run spec-kit commands in both simultaneously, verify each worktree's
flow state tracks its own feature independently.

**Acceptance Scenarios**:

1. **Given** two worktrees for features A and B, **When** spec-kit
   commands run in both worktrees, **Then** each worktree's
   `.specify/.spex-state` tracks its own feature independently.

2. **Given** feature A's worktree is in the "implement" phase, **When**
   feature B's worktree starts the "specify" phase, **Then** feature A's
   state is unaffected.

3. **Given** a worktree is deleted after its PR is merged, **When** the
   contributor checks the project-specs repo, **Then** archived specs
   for that feature are still present.

---

### Edge Cases

- What happens when `spex-finish` is run but no spec artifacts exist
  in the worktree? (Treat as normal finish, no clean branch needed.)
- What happens when the archive path is unreachable (unmounted drive,
  wrong path)? (Warn the user, proceed with clean branch creation
  without archiving.)
- What happens when the feature branch has no code changes, only spec
  artifacts? (Warn the user that the clean PR branch would be empty.)
- What happens when `.specify/` is accidentally committed to the PR
  branch? (The finish command should verify the clean branch contains
  no spec directories before reporting success.)

## Clarifications

### Session 2026-06-25

- Q: How should the clean PR branch be created (mechanism)? → A: Squash onto base: diff the feature branch against its merge-base with the upstream default branch, apply only non-spec changes as a single commit.
- Q: How is upstream mode enabled during `specify init`? → A: Interactive prompt during init (like other extensions). The entire feature is packaged as an extension bundle (similar to `spex-collab`).
- Q: What should the extension be named? → A: `spex-detach`. Description: "Detach spec artifacts at PR time for contributing to projects that don't use spec-driven development."
- Q: What exactly gets archived to the project-specs repo? → A: Both `specs/<feature>/` and `.specify/` (full design context including spec, plan, tasks, flow state, and spec-kit configuration).
- Q: What naming convention for the clean PR branch? → A: `pr/<feature-branch-name>` (direct mapping, e.g., feature branch `fix-auth-bug` becomes `pr/fix-auth-bug`).

## Requirements

### Functional Requirements

- **FR-001**: The feature MUST be packaged as a spex extension bundle
  (like `spex-collab`). `specify init` MUST offer an interactive
  prompt to enable this extension, consistent with how other
  extensions are activated.
- **FR-002**: The `spex-detach` extension MUST be disabled by default,
  preserving existing single-repo behavior for all users.
- **FR-003**: When `spex-detach` is enabled, `spex-finish` MUST create
  a clean PR branch by computing the diff between the feature branch
  and its merge-base with the upstream default branch, filtering out
  changes to `.specify/`, `specs/`, and `brainstorm/` directories,
  and applying the remaining changes as a single squashed commit on
  a new branch named `pr/<feature-branch-name>`. The upstream default
  branch is auto-detected from the remote HEAD or overridden via
  `upstream.default_branch` in the extension config. This ensures no
  spec artifacts appear in the branch history.
- **FR-004**: The original feature branch MUST remain unchanged after
  clean PR branch creation (specs intact for continued work).
- **FR-005**: When `spex-detach` is enabled and an archive path is
  configured, `spex-finish` MUST copy both the `specs/<feature>/`
  directory (spec.md, plan.md, tasks.md) and the `.specify/`
  directory (configuration, flow state) to the archive path before
  creating the clean PR branch.
- **FR-006**: The archive MUST organize specs by project name and
  feature name (e.g., `archive/project-name/feature-name/`). The
  project name MUST be derived from the git remote name of the
  upstream repository (e.g., `origin` remote's `owner/repo` yields
  the project name). If no remote is configured, the current
  directory name is used as fallback.
- **FR-007**: Each worktree MUST have independent `.specify/` state
  when `spex-detach` is enabled (this is inherent in the worktree
  model since each worktree has its own files).
- **FR-008**: The clean PR branch MUST be verifiable: `spex-finish`
  MUST check that no spec directories remain before reporting success.
- **FR-009**: Brainstorm documents MUST be created in the project-specs
  repo, not in code worktrees, when the contributor is working in
  `spex-detach` mode. The project-specs repo path is stored in the
  extension's config file (`spex-detach-config.yml`) as `archive.path`.
  The brainstorm command MUST read this config to determine where to
  write brainstorm documents.
- **FR-010**: Re-running `spex-finish` on a feature branch MUST
  regenerate the clean PR branch (idempotent operation).

### Key Entities

- **Project-specs repo**: A personal repository owned by the
  contributor that stores brainstorm documents and archived specs
  across all upstream project contributions. Always on the `main`
  branch.
- **Code worktree**: A git worktree of the upstream project's fork,
  containing a feature branch with both code and spec artifacts
  during development.
- **Clean PR branch**: A derivative branch created from the feature
  branch with all spec directories removed, used for upstream PRs.
- **Archive**: A directory within the project-specs repo where
  completed spec artifacts are stored, organized by project and
  feature.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Contributors can submit PRs to upstream projects that
  contain zero spec-related files or directories.
- **SC-002**: Multiple features can be developed in parallel across
  separate worktrees without state interference.
- **SC-003**: All spec-kit commands work identically during the
  specify/plan/implement phases regardless of whether `spex-detach`
  is enabled.
- **SC-004**: Spec artifacts for completed features are retrievable
  from the project-specs repo archive after the code worktree is
  deleted.
- **SC-005**: The clean PR branch creation adds no more than one
  additional step to the existing finish workflow.

## Assumptions

- The contributor has a personal project-specs repo set up for
  archiving. The feature does not create this repo automatically.
- Git worktrees are the isolation mechanism for parallel feature work.
  Each worktree is initialized with `specify init` independently.
- The upstream project uses GitHub or a similar forge where PRs are
  branch-to-branch diffs.
- The `spex-finish` command is the natural integration point for
  clean branch creation and archiving, since it already handles
  feature completion.
- Brainstorm documents that reference multiple upstream projects are
  managed manually in the project-specs repo (no automated
  cross-project linking in v1).
