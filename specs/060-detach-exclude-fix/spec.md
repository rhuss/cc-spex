# Feature Specification: Detach Stealth-Mode Exclude Gap and Config Loss on Refresh

**Feature Branch**: `060-detach-exclude-fix`

**Created**: 2026-11-03

**Status**: Draft

**Input**: Deliverable 1 (bug fix) of brainstorm #54 (`brainstorm/54-detach-mode-at-init.md`, revisit 2026-11-03): selecting spex-detach during setup must actually hide spec artifacts from git and prove it; a refresh must keep the user's detach configuration and repair projects that were set up before the fix.

## Background

spex-detach ("stealth mode") hides spec artifacts (by default `.specify/`, `specs/`, `brainstorm/`) from git in projects that do not use spec-driven development, typically forks of upstream projects. It does so by writing the configured exclude paths into the clone's local exclude file, which every worktree of the clone shares.

Two defects were found by reading the code after a real-world near-leak (a fork where spec files, the spex project declaration and the constitution were visible to git while detach reported itself as enabled):

1. **Exclude gap on setup.** Selecting spex-detach during `/spex:init` (and the equivalent Codex setup) enables the extension but never writes its exclude entries. The step that writes them runs before the user's selection is applied, while spex-detach is still deliberately disabled, so it does nothing. The later step that applies the selection enables the extension but does not write the entries either.
2. **Config loss on refresh.** `/spex:init --refresh` (and the Codex setup re-run) uninstalls and reinstalls spex-detach, which deletes its configuration file and replaces it with the template. A configured archive path, custom exclude paths and the auto-commit setting are silently reset.

## Clarifications

### Session 2026-11-03

- Q: Which files does the verification probe for each configured exclude path? → A: A generic probe file under each configured path, plus every file spex itself re-includes by negation rule (the project declaration and the constitution) when it lies under a configured path.
- Q: When the existing detach configuration cannot be preserved during reinstall, does setup stop or continue? → A: The configuration is saved before anything is uninstalled. If saving fails, the whole setup or refresh stops with an error naming the configuration file, and nothing is changed (user decision, review-spec).
- Q: Should refresh merge keys that a newer configuration template adds into the user's preserved configuration? → A: No. The preserved file is kept byte-identical; missing keys fall back to their defaults when read. Changed defaults in a later release reach only new installs (user decision, review-spec).
- Q: How are exclude entries that are not directories verified? → A: A directory entry (trailing `/`) is probed with a file under it; a file entry is probed as that path; a glob entry is probed with a synthetic file name that matches it (user decision, review-spec).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Selecting detach at setup really hides spec artifacts (Priority: P1)

A developer sets up spex in a fork of a project that does not use spec-driven development and selects spex-detach. When setup finishes, every configured spec artifact path is invisible to git, and setup says so only after checking it. If any path is still visible, setup says which one and that stealth mode is not fully active.

**Why this priority**: This is the leak. Without it, one `git add -A` puts spec files, the project declaration and the constitution into an upstream pull request, which is exactly what detach exists to prevent.

**Independent Test**: In a fresh test repository, run setup with spex-detach selected, create a file under each configured path, and confirm git reports every one of them as ignored, and that the setup output contains the verification result.

**Acceptance Scenarios**:

1. **Given** a git repository without spex, **When** the user runs setup and selects spex-detach, **Then** every configured exclude path is present in the clone's local exclude file and git reports a probe file under each path as ignored.
2. **Given** setup with spex-detach selected, **When** setup finishes, **Then** its output states that stealth mode is active and lists the verified paths.
3. **Given** setup with spex-detach selected and one configured path that git still does not ignore (for example because a negation rule elsewhere re-includes it, or the path is already tracked), **When** setup finishes, **Then** the output names that path in a warning and does not state that stealth mode is fully active.
4. **Given** a project where spex-detach was disabled, **When** the user re-runs setup and newly selects spex-detach, **Then** the same writing and verification happen as on a first setup.
5. **Given** the spex project declaration and the constitution under `.specify/`, **When** setup with spex-detach selected finishes, **Then** git reports both as ignored (the detach exclusion of `.specify/` takes precedence over spex's own re-include rules for these files).

---

### User Story 2 - Refresh keeps the user's detach configuration (Priority: P2)

A developer has configured spex-detach (for example set an archive path to a sibling specs repository, changed the exclude paths, or turned auto-commit off) and later runs a refresh to pick up a new spex version. After the refresh, the configuration is exactly as before.

**Why this priority**: Losing the archive path silently stops brainstorms and specs from being archived to the specs repository; losing custom exclude paths can re-expose artifacts. It is data loss, but only after a refresh, so it ranks below the leak.

**Independent Test**: Write a detach configuration with non-default values, run a refresh, and compare the configuration file before and after.

**Acceptance Scenarios**:

1. **Given** a detach configuration with a non-empty archive path, auto-commit set to false, and a custom exclude path list, **When** the user runs a refresh, **Then** all three values are unchanged afterwards.
2. **Given** a detach configuration with user comments or extra keys, **When** the user runs a refresh, **Then** the file content is preserved as it was.
3. **Given** a project where spex-detach is installed but disabled, with a customized configuration, **When** the user runs a refresh, **Then** the configuration is preserved as well (it is kept for a later re-enable).
4. **Given** a project with spex-detach installed but no configuration file, **When** the user runs a refresh, **Then** the template configuration is installed as today.

---

### User Story 3 - Refresh repairs projects set up before the fix (Priority: P3)

A developer selected spex-detach before this fix, so the exclude entries were never written (or only some of them). The next refresh detects that detach is enabled but its entries are missing, writes them, verifies them, and reports that it repaired stealth mode.

**Why this priority**: Existing affected projects stay exposed until repaired. The repair piggybacks on the refresh users run anyway, so they need not know about the bug.

**Independent Test**: Enable spex-detach in a test repository, remove its exclude entries by hand, run a refresh, and confirm the entries are back, the output mentions the repair, and a second refresh adds nothing.

**Acceptance Scenarios**:

1. **Given** spex-detach enabled and none of its exclude entries in the local exclude file, **When** the user runs a refresh, **Then** all configured entries are written, verified, and the output reports a repair naming the added paths.
2. **Given** spex-detach enabled and only some of its entries present, **When** the user runs a refresh, **Then** only the missing entries are added and the repair report names just those.
3. **Given** spex-detach enabled and all entries present, **When** the user runs a refresh, **Then** nothing is added, no repair is reported, and the verification result is still shown.
4. **Given** any state, **When** the user runs refresh twice in a row, **Then** the local exclude file contains each configured entry exactly once.

---

### User Story 4 - Projects without detach are unaffected (Priority: P3)

A developer who does not use spex-detach runs setup or refresh. Nothing about the local exclude file or the output differs from today. The only difference is that an existing detach configuration file is now kept as it is instead of being replaced by the template (FR-007).

**Why this priority**: Guard against regressions for the default (non-fork) case, which is the majority of projects.

**Independent Test**: Run setup and refresh without spex-detach selected and compare the local exclude file and output with the behavior before the change.

**Acceptance Scenarios**:

1. **Given** setup without spex-detach selected, **When** setup finishes, **Then** no detach exclude entries are written and no stealth-mode verification output appears.
2. **Given** spex-detach installed but disabled, **When** the user runs a refresh, **Then** no detach exclude entries are written and no repair is reported.

---

### Edge Cases

- **Path already tracked by git**: a configured path has files committed on the current branch. Excluding cannot hide tracked files, so verification reports the path as visible, together with the existing hint that tracked files must be removed from history separately.
- **Custom exclude paths**: the user configured a different path list. Writing, verification and repair use the configured list, not the defaults.
- **Exclude entry written but still not ignored**: another rule (for example a later negation rule) re-includes a path. Verification catches it and warns, naming the path.
- **Configuration unreadable** (missing YAML tool or invalid file): the detach tooling falls back to the default path list, as today. Verification uses the same list that was written, so the two never disagree.
- **Not a git repository**: detach steps are skipped without failing setup, as today.
- **Worktrees**: the local exclude file is shared by all worktrees of a clone, so running setup or refresh from a worktree protects the main checkout and every other worktree.
- **Setup fails before the selection is applied**: spex-detach stays disabled and nothing is written (existing safety behavior is kept).
- **Deselecting spex-detach in setup**: existing exclude entries are left as they are (behavior unchanged; this errs on the side of hiding). Removing them stays a deliberate step through the detach command.

## Requirements *(mandatory)*

### Functional Requirements

**Exclude entries on setup**

- **FR-001**: When the extension selection is applied and spex-detach ends up enabled, spex MUST write every configured exclude path into the clone's local exclude file. This MUST hold for both setup paths (the Claude Code `/spex:init` flow and the Codex setup flow), for first-time setup, re-runs and refreshes.
- **FR-002**: After writing, spex MUST verify each configured exclude path by asking git whether a probe for that path is ignored. The probe depends on the entry's form: for a directory entry (ending in `/`) it is a file under that directory; for a plain file entry it is the path itself; for a glob entry it is a synthetic file name that matches the glob. In addition, every file that spex's own generated-file rules re-include by negation (the project declaration and the constitution) MUST be probed when it lies under a configured exclude path, because a directory-level probe alone would not catch a re-include. A configured path also counts as visible when git tracks any file under it, because git reports an untracked probe file under a tracked directory as ignored even though the tracked files stay visible; the verification MUST therefore check for tracked files under each path in addition to the probe.
- **FR-003**: If every configured path is ignored, the setup or refresh output MUST state that stealth mode is active and list the verified paths.
- **FR-004**: If any configured path is not ignored, the setup or refresh output MUST show a warning naming each such path, and MUST NOT state that stealth mode is active. When the path is visible because it is already tracked, the warning MUST say so. A visible path MUST NOT make setup or refresh fail; the remaining steps still run.
- **FR-005**: The writing and verification MUST be idempotent: running them again adds no duplicate entries.
- **FR-006**: The verification MUST be available on its own (independently of setup), so that it can be tested and re-run without changing anything.

**Configuration preserved on refresh**

- **FR-007**: When spex-detach is reinstalled during setup or refresh and a detach configuration file exists, its content MUST be identical afterwards. This applies whether spex-detach is enabled or disabled.
- **FR-008**: When no detach configuration file exists, setup MUST install the template configuration as today.
- **FR-009**: The existing configuration MUST be saved before any extension is uninstalled. If saving fails, the whole setup or refresh MUST stop with an error naming the configuration file, before anything is changed. The configuration MUST never be replaced by the template in that case.
- **FR-009a**: The preserved configuration MUST NOT be merged with a newer template. Keys the user's file lacks keep falling back to their defaults when read, as today.

**Repair on refresh**

- **FR-010**: On every setup or refresh where spex-detach ends up enabled, missing configured exclude entries MUST be added (this is FR-001 applied to existing projects). When at least one entry was added to a project in which spex-detach was already enabled before the run, the output MUST report it as a repair and name the added paths.
- **FR-011**: When all entries are already present, no repair MUST be reported.

**No change for other projects**

- **FR-012**: When spex-detach is not enabled after the selection is applied, setup and refresh MUST NOT write detach exclude entries, MUST NOT print stealth-mode verification or repair output, and MUST NOT change behavior otherwise.

**Tests and docs**

- **FR-013**: Automated tests MUST cover: setup with spex-detach selected (entries written, verified, active message) for both setup flows (`/spex:init` and the Codex setup workflow), the project declaration and the constitution reported as ignored, a visible-path warning (including a path with tracked files), configuration preservation across refresh (enabled and disabled), the preservation-failure path (error names the file, original left in place), repair of missing entries (none and partial), idempotence across two refreshes, and the no-detach case.
- **FR-014**: User-facing documentation (README and `spex/docs/help.md`) MUST describe that selecting spex-detach in setup writes and verifies the exclude entries, and that refresh keeps the detach configuration and repairs missing entries.

### Key Entities

- **Detach configuration**: per-project settings for spex-detach: archive path, auto-commit flag, list of exclude paths. Lives inside the installed extension's directory, which reinstalling replaces.
- **Local exclude file**: the clone-local list of ignore rules (not committed, shared across worktrees). Holds the detach entries under a marker comment plus spex's own generated-file rules.
- **Configured exclude paths**: the paths spex-detach must hide; defaults `.specify/`, `specs/`, `brainstorm/`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of test runs where spex-detach is selected at setup, git reports a probe file under every configured path as ignored when setup completes, or the output names each path that is not.
- **SC-002**: Stealth mode is never reported as active while any configured path is visible to git (0 occurrences across the test matrix).
- **SC-003**: A customized detach configuration is byte-identical before and after a refresh in 100% of test runs.
- **SC-004**: A project with missing detach entries is fully protected after a single refresh, and after any number of further refreshes each entry appears exactly once.
- **SC-005**: Setup and refresh output and the local exclude file for projects without spex-detach enabled are unchanged compared with the previous release.

## Assumptions

- The fix covers spex-detach only. Other spex extensions also lose their configuration when reinstalled; that is a separate issue and out of scope here.
- The detach configuration stays where it is today (inside the installed extension's directory); preserving it across reinstall is sufficient. Moving it is out of scope.
- Hiding the spex project declaration and the constitution in detach mode is intended, as decided in brainstorm #54.
- Because the preserved configuration is never merged with the template, a change to the default values in a later release (for example a new default exclude path) reaches only new installs. Existing projects keep their file as it is, including projects that never edited it.
- Disabling spex-detach through the setup selection keeps today's behavior (entries stay until the user runs the detach command's disable action).
- Out of scope (brainstorm #54, Deliverable 2): setup asking for the archive path, creating a specs repository or remote, auto-push, versioning the project declaration and constitution in the specs repository, fork detection.
