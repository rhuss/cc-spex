# Feature Specification: Detach Stealth Mode

**Feature Branch**: `045-detach-stealth-mode`
**Created**: 2026-07-21
**Status**: Draft
**Input**: Brainstorm #23 (Revisit 2026-07-21): Replace pr/ branch stripping with .git/info/exclude stealth mode

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Stealth Mode for Upstream Contributions (Priority: P1)

A developer using spex to contribute to an upstream/brownfield project that does not use spec-driven development enables the detach extension. From that point forward, all spec artifacts (.specify/, specs/, brainstorm/) are invisible to git. The developer can freely run `git add .`, switch branches, rebase on upstream, and create PRs without any spec files leaking into commits or pull requests.

**Why this priority**: This is the core value proposition. Without leak prevention, the entire detach extension is unreliable for upstream contributions.

**Independent Test**: Enable the detach extension in a test repo, create spec files, then verify that `git add .`, `git status`, and rebase operations never include spec artifacts.

**Acceptance Scenarios**:

1. **Given** the detach extension is enabled, **When** a developer runs `git add .` or `git add -A`, **Then** no files under .specify/, specs/, or brainstorm/ are staged
2. **Given** the detach extension is enabled, **When** a developer runs `git status`, **Then** no files under .specify/, specs/, or brainstorm/ appear as untracked
3. **Given** spec files exist as excluded files and the developer rebases on upstream main, **Then** no spec files are carried into the rebased commits
4. **Given** the detach extension is enabled, **When** a developer runs `git add -f .specify/somefile`, **Then** the file IS staged (force-add is an intentional override, not a leak)

---

### User Story 2 - Archive Specs at Finish Time (Priority: P2)

When a developer finishes a feature (via spex-finish), the spec artifacts are automatically archived to a configured sibling specs repository for version control and future reference. This happens before the feature branch is cleaned up.

**Why this priority**: Since spec files are untracked in the code repo, they have no version control there. Archiving to a sibling repo provides the historical record.

**Independent Test**: Configure a sibling specs repo path, finish a feature, and verify that .specify/, specs/, and brainstorm/ are copied and committed to the sibling repo.

**Acceptance Scenarios**:

1. **Given** a sibling specs repo is configured and the developer runs spex-finish, **When** the finish hook executes, **Then** spec artifacts are copied to the sibling repo under a project/feature directory structure
2. **Given** a sibling specs repo is configured and contains previous archives, **When** a new feature is archived, **Then** existing archives are not overwritten or corrupted
3. **Given** no sibling specs repo is configured, **When** the developer runs spex-finish, **Then** the archive step is skipped with a warning and finish proceeds normally

---

### User Story 3 - Enable/Verify Exclude Entries (Priority: P3)

A developer can manually run a command to set up or verify the .git/info/exclude entries. This is useful for existing clones where the extension was enabled after initial setup, or to verify that entries haven't been accidentally removed.

**Why this priority**: The automatic setup during init handles new clones. This manual command covers existing clones and troubleshooting.

**Independent Test**: Run the enable command on a repo without exclude entries, verify they are added. Run it again, verify it is idempotent. Run it on a repo with existing entries, verify they are preserved.

**Acceptance Scenarios**:

1. **Given** a repo without spec paths in .git/info/exclude, **When** the enable command runs, **Then** .specify/, specs/, and brainstorm/ entries are added
2. **Given** a repo that already has the entries, **When** the enable command runs again, **Then** no duplicate entries are created
3. **Given** a repo with existing custom entries in .git/info/exclude, **When** the enable command runs, **Then** existing entries are preserved and spec entries are appended
4. **Given** a repo where spec files are already tracked (committed), **When** the enable command runs, **Then** a warning is displayed indicating that tracked files must be removed from git history separately

---

### Edge Cases

- What happens when .git/info/ directory does not exist? Create it before writing exclude entries.
- What happens when spec files were previously committed to a branch before detach was enabled? Warn the user; exclude only prevents future staging, not historical commits.
- What happens when the sibling specs repo path is configured but the directory does not exist at archive time? Fail with a clear error message.
- What happens when two features are archived to the same sibling repo concurrently? Each archives to a separate project/feature subdirectory; no conflict.
- What happens when the developer is not in a git repository? The enable command fails with a clear error (no .git/ directory to write exclude entries to).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The `enable` subcommand MUST write .specify/, specs/, and brainstorm/ entries to .git/info/exclude
- **FR-002**: The `enable` subcommand MUST be idempotent (running it multiple times produces the same result)
- **FR-003**: The `enable` subcommand MUST create the .git/info/ directory if it does not exist
- **FR-004**: The `enable` subcommand MUST preserve existing entries in .git/info/exclude
- **FR-005**: The `enable` subcommand MUST warn if spec files are currently tracked by git
- **FR-006**: The `enable` subcommand MUST run automatically during `specify init` via the extension's `after_init` lifecycle hook when the detach extension is active
- **FR-007**: The `archive` subcommand MUST copy all configured strip paths (default: .specify/, specs/, brainstorm/) to the configured sibling specs repo path
- **FR-008**: The `archive` subcommand MUST organize archived specs under `<project-name>/<feature-branch-name>/` in the sibling repo, preserving the original directory structure within each artifact directory
- **FR-009**: The `archive` subcommand MUST auto-commit the archived files to the sibling specs repo when configured to do so
- **FR-010**: The `before_finish` hook MUST invoke the archive subcommand when detach is enabled and an archive path is configured
- **FR-011**: The `before_finish` hook MUST skip archiving gracefully when no archive path is configured
- **FR-012**: The old `detach` subcommand (pr/ branch stripping) MUST be removed
- **FR-013**: The old `verify` subcommand MUST be removed
- **FR-014**: The old `clean-branch-name` subcommand MUST be removed
- **FR-015**: The `is-enabled` subcommand MUST be preserved for other extensions to check detach state. It MUST return exit code 0 when the extension directory exists at `.specify/extensions/spex-detach`, and exit code 1 otherwise
- **FR-016**: The default mode (no detach extension) MUST remain unchanged, with all spec files committed to the repo

### Key Entities

- **Exclude Entry**: A line in .git/info/exclude that prevents git from tracking a specific path pattern
- **Sibling Specs Repo**: A separate git repository located alongside the code repo, used to archive spec artifacts for version control
- **Archive**: A copy of spec artifacts organized by project and feature within the sibling specs repo

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero spec artifacts appear in any git commit or PR after the detach extension is enabled
- **SC-002**: The enable command completes in under 1 second and is safe to run repeatedly without side effects
- **SC-003**: Archived specs are retrievable from the sibling repo with standard git operations (clone, log, show)
- **SC-004**: Existing spex workflows (specify, plan, implement, review, finish) function normally with spec files as excluded (untracked) files
- **SC-005**: No changes are required to the upstream project's .gitignore or any committed file

## Smoke Test

1. Enable detach on a test clone of an upstream repo, create spec files via specify init, and verify `git status` shows no spec artifacts
2. Run `git add . && git diff --cached --name-only` and verify zero spec files are staged
3. Configure a sibling specs repo, finish a feature, and verify specs are archived and committed in the sibling repo
4. After finishing, switch to main branch and verify spec files are still on disk and accessible for future reference

## Out of Scope

- Modifying the upstream project's `.gitignore` or any committed files
- Per-commit version control of spec artifacts within the code repo (feature-completion archiving to sibling repo is the mechanism)
- Rewriting git history to remove previously committed spec artifacts (user responsibility; `enable` warns about this case)
- Supporting non-git version control systems

## Assumptions

- The developer has a separate git repository (sibling specs repo) for archiving spec artifacts. If not configured, archiving is skipped without error.
- The .git/info/exclude mechanism is supported by all git versions in common use (it has been part of git since its earliest versions).
- Spec files do not need per-commit version control within the code repo during active development. Feature-completion archiving provides sufficient historical record.
- The detach extension is opt-in. Projects that commit spec artifacts to the repo (the default behavior) are unaffected.
- Other spex extensions (worktrees, gates, teams) continue to function with excluded spec files since they resolve paths via cwd, not git tracking.
- The configurable strip paths in spex-detach-config.yml continue to be respected, with .specify/, specs/, and brainstorm/ as defaults.
- The `upstream.default_branch` config key and the `detach` config section (used by the old pr/ branch approach) will be removed from config-template.yml since they are no longer needed.
