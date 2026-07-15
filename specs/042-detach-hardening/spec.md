# Feature Specification: Harden spex-detach for Reliable Upstream Contributions

**Feature Branch**: `042-detach-hardening`
**Created**: 2026-07-14
**Status**: Draft
**Input**: Brainstorm #37 (spex-detach-hardening), Spec 029 (upstream-contrib-mode)

## User Scenarios & Testing

### User Story 1 - Finish with automatic detach and archive (Priority: P1)

A developer working on a fork of an upstream project runs `spex-finish` after implementation. The finish command detects that `spex-detach` is enabled, automatically archives spec artifacts to the sibling specs repo, creates a clean PR branch with all SpecKit content stripped, and offers to push the clean branch. The upstream PR contains zero spec artifacts.

**Why this priority**: This is the core gap. Without finish integration, detach is effectively unusable since users must remember to run it manually, which they don't.

**Independent Test**: Run `spex-finish` in a project with `spex-detach` enabled and `archive.path` configured. Verify the clean `pr/<branch>` branch contains no `.specify/`, `specs/`, or `brainstorm/` content, and that the sibling specs repo received the archived artifacts.

**Acceptance Scenarios**:

1. **Given** a feature branch with spec artifacts and `spex-detach` enabled with `archive.path` configured, **When** the user runs `spex-finish`, **Then** specs, brainstorms, and `.specify/` are moved to the sibling specs repo, a clean `pr/<branch>` branch is created, and "Push clean PR branch" appears as an option in Phase 4.
2. **Given** a feature branch with `spex-detach` enabled but no `archive.path` configured, **When** the user runs `spex-finish`, **Then** the detach still creates the clean PR branch (archive is skipped with a warning), and the user is offered the push option.
3. **Given** `spex-detach` is enabled and `--skip-archive` is passed, **When** `spex-finish` runs, **Then** the archive step is skipped but the clean PR branch is still created.

---

### User Story 2 - Post-detach verification catches leaked artifacts (Priority: P1)

After the clean PR branch is created, the detach script automatically verifies that no SpecKit fingerprints remain in the PR's changes. If any spec artifacts leaked through (e.g., a file placed outside the configured `strip_paths`), the detach fails with a clear error listing the leaked files.

**Why this priority**: Without verification, the detach could silently produce a PR branch that still contains spec content, defeating the entire purpose.

**Independent Test**: Intentionally add a spec-like file outside `strip_paths`, run detach, and verify it reports the leak and fails.

**Acceptance Scenarios**:

1. **Given** a clean PR branch was just created, **When** the verification step runs, **Then** it checks `git diff` against the merge base for any files matching SpecKit fingerprints (`.specify/`, `specs/` with spec.md/plan.md/tasks.md, `brainstorm/`).
2. **Given** the PR branch contains a leaked `.specify/memory/constitution.md` file, **When** verification runs, **Then** the detach fails with an error listing the leaked file path.
3. **Given** the upstream base branch already contains a directory named `specs/`, **When** verification runs, **Then** only files in the PR's diff are checked (upstream content is not flagged).

---

### User Story 3 - Brainstorm skill uses correct detach script path (Priority: P2)

When brainstorming in a project with `spex-detach` enabled and `archive.path` configured, the brainstorm skill correctly redirects output to the sibling specs repo's `brainstorm/` directory. The detach-awareness check does not silently fail due to a wrong script path.

**Why this priority**: A bug fix. The current code references the wrong path, causing silent failure. Low risk to fix but important for the sibling specs repo workflow.

**Independent Test**: Run `/speckit-spex-brainstorm` in a project with `spex-detach` enabled and `archive.path` set. Verify the brainstorm document is created in the sibling specs repo.

**Acceptance Scenarios**:

1. **Given** `spex-detach` is enabled and `archive.path` is set to `../project-specs`, **When** the brainstorm skill checks for detach awareness, **Then** it reads the script at `.specify/extensions/spex-detach/scripts/spex-detach.sh` (not the incorrect `.specify/extensions/spex/scripts/spex-detach.sh`).
2. **Given** the detach check succeeds, **When** a brainstorm document is written, **Then** it is created in `<archive.path>/brainstorm/` instead of the local `brainstorm/` directory.

---

### User Story 4 - Archive moves artifacts with brainstorms included (Priority: P2)

When archiving at detach time, the archive operation moves (not copies) all three artifact directories (`.specify/`, `specs/`, `brainstorm/`) to the sibling specs repo. After the move, the source directories no longer exist in the code fork, and the sibling repo has a committed copy.

**Why this priority**: Move semantics prevent orphaned spec dirs in the code fork and ensure the sibling specs repo is the authoritative location.

**Independent Test**: Run archive with move semantics, verify source dirs are deleted and target repo has a new commit with the artifacts.

**Acceptance Scenarios**:

1. **Given** `archive.path` is configured and all three directories exist, **When** archive runs during detach, **Then** `.specify/`, `specs/<feature>/`, and `brainstorm/` are copied to the sibling repo, committed, and deleted from the source.
2. **Given** archive succeeds but source deletion fails (permissions), **When** archive runs, **Then** the archive is committed to the sibling repo but a warning is emitted about source cleanup.

---

### User Story 5 - Fork detection warns about missing .gitignore entries (Priority: P3)

When `spex-detach` is enabled and the repo has an `upstream` remote, the detach flow checks whether `.gitignore` includes SpecKit paths (`.specify/`, `specs/`, `brainstorm/`). If any are missing, it emits a non-blocking advisory warning.

**Why this priority**: Defense-in-depth. Prevents `git add .` from staging spec artifacts even when someone skips `spex-finish`. Advisory only, not a blocker.

**Independent Test**: Set up a repo with an `upstream` remote and no `.gitignore` entries for spec paths. Run detach and verify the warning appears.

**Acceptance Scenarios**:

1. **Given** the repo has an `upstream` remote and `.gitignore` does not include `.specify/`, **When** detach runs, **Then** a warning is emitted recommending the addition of `.specify/`, `specs/`, and `brainstorm/` to `.gitignore`.
2. **Given** the repo has an `upstream` remote and `.gitignore` already includes all three paths, **When** detach runs, **Then** no warning is emitted.
3. **Given** the repo has no `upstream` remote, **When** detach runs, **Then** the `.gitignore` check is skipped entirely.

---

### User Story 6 - Brainstorm discovery from sibling specs repo (Priority: P3)

When brainstorming in the code fork, the brainstorm skill also scans the sibling specs repo's `brainstorm/` directory for existing documents on similar topics, presenting matches alongside local brainstorm matches.

**Why this priority**: Prevents duplicate brainstorms across the code fork and sibling specs repo. Nice-to-have for workflow continuity.

**Independent Test**: Create a brainstorm document in the sibling specs repo, then start a brainstorm session on a similar topic in the code fork. Verify the sibling document appears in the revisit detection results.

**Acceptance Scenarios**:

1. **Given** `spex-detach` is enabled with `archive.path` set and `<archive.path>/brainstorm/` contains documents, **When** the brainstorm skill runs revisit detection, **Then** sibling repo documents are included alongside local matches.
2. **Given** the user chooses to update an existing sibling brainstorm, **When** the session completes, **Then** a revisit section is appended to the document in the sibling repo.

---

### User Story 7 - Init auto-detects sibling specs repo (Priority: P3)

When `spex-detach` is enabled during `specify init`, the init flow auto-detects sibling `*-specs` directories and suggests one as the default `archive.path`. If no sibling directory is found, it falls back to asking the user explicitly.

**Why this priority**: Convenience for the common naming convention. Reduces friction during initial setup.

**Independent Test**: Run `specify init` with `spex-detach` enabled in a directory where a sibling `*-specs` directory exists. Verify it is suggested as the default.

**Acceptance Scenarios**:

1. **Given** the project is at `~/Work/openshell/` and `~/Work/openshell-specs/` exists, **When** `specify init` runs with `spex-detach` enabled, **Then** `../openshell-specs` is suggested as the default `archive.path`.
2. **Given** no sibling `*-specs` directory exists, **When** `specify init` runs, **Then** the user is prompted to enter `archive.path` manually.

---

### Edge Cases

- What happens when detach runs but there are no code changes (all changes are spec-only)? The detach already handles this with exit code 2 and an "empty" flag.
- What happens when archive.path points to a non-existent directory? The archive command already fails with a clear error.
- What happens when the sibling specs repo has uncommitted changes? The archive auto-commit should still work since it only stages the archived files.
- What happens when spex-finish is run multiple times? The detach is idempotent (deletes and recreates the `pr/<branch>` branch).
- What happens when `--skip-archive` is used but `archive.path` is not configured? The skip flag is a no-op since archive would not run anyway.
- What happens when `.specify/` is deleted as part of move semantics but finish still needs it? The deletion is staged but not committed until the final squash, so `.specify/` remains on disk throughout the finish flow. Post-completion hooks and state cleanup run before the squash commit incorporates the deletion.

## Requirements

### Functional Requirements

- **FR-001**: The `spex-finish` command MUST detect when `.specify/extensions/spex-detach` exists and invoke the detach flow after Phase 3 Step 1 (commit outstanding changes) but before the squash (Phase 3 Step 2+). This requires direct integration in the finish command rather than the existing `before_finish` hook, which fires too early (before Phase 1).
- **FR-002**: The `spex-finish` command MUST offer "Push clean PR branch" as an option in Phase 4 when detach creates a `pr/<branch>` branch.
- **FR-003**: The detach flow MUST archive specs, brainstorms, and `.specify/` to the sibling specs repo (when `archive.path` is configured) before stripping artifacts from the PR branch. Archive is default-on, skippable with `--skip-archive`.
- **FR-004**: The archive operation MUST use move semantics (delete source after successful copy and commit to the archive repo) when invoked as part of the detach flow. Source deletion MUST occur after the clean PR branch has been created and verified, and after all finish phases that reference `.specify/` (including post-completion hooks) have completed. In practice, the deletion is committed as part of the squash on the feature branch, ensuring the fork's main stays clean while `.specify/` remains available throughout the finish flow.
- **FR-005**: The brainstorm skill MUST reference the detach script at `.specify/extensions/spex-detach/scripts/spex-detach.sh` (fix incorrect path).
- **FR-006**: After creating the clean PR branch, the detach script MUST verify that no SpecKit fingerprints remain in the PR's changes by checking `git diff --name-only` against the merge base for files matching: `.specify/` (any path), `specs/*/spec.md`, `specs/*/plan.md`, `specs/*/tasks.md`, and `brainstorm/*.md`. The fingerprint patterns MUST be derived from the configured `strip_paths` rather than hardcoded.
- **FR-007**: The verification step MUST fail with a clear error listing any leaked files if SpecKit artifacts are found in the PR diff.
- **FR-008**: When `spex-detach` is enabled and an `upstream` remote exists, the detach flow MUST check `.gitignore` for SpecKit paths and emit a non-blocking warning if any are missing.
- **FR-009**: The brainstorm skill MUST scan the sibling specs repo's `brainstorm/` directory for existing documents during revisit detection (when `archive.path` is configured).
- **FR-010**: The `specify init` flow MUST auto-detect sibling `*-specs` directories and suggest as default `archive.path` when `spex-detach` is enabled. It MUST fall back to explicit prompt if no match.
- **FR-011**: Running `spex-finish` multiple times MUST regenerate the clean PR branch cleanly (idempotent via delete + recreate).
- **FR-012**: The archive operation MUST include `brainstorm/` alongside `specs/` and `.specify/` in the set of directories moved to the sibling specs repo.

### Key Entities

- **spex-detach-config.yml**: Configuration file for the detach extension. Contains `archive.path`, `upstream.default_branch`, and `detach.strip_paths`.
- **spex-detach.py**: Python script implementing detach, archive, and clean-branch-name subcommands (existing), plus a new `verify` subcommand to be added by this feature.
- **speckit.spex.finish.md**: The finish command skill file where detach integration must be wired in.
- **speckit.spex.brainstorm.md**: The brainstorm skill file containing the incorrect script path reference.
- **pr/<branch>**: The clean PR branch created by detach, containing only code changes without spec artifacts.

## Success Criteria

### Measurable Outcomes

- **SC-001**: After running `spex-finish` with `spex-detach` enabled, the resulting `pr/<branch>` branch contains zero files matching `.specify/`, `specs/*/spec.md`, `specs/*/plan.md`, `specs/*/tasks.md`, or `brainstorm/` in its diff against the upstream base.
- **SC-002**: The brainstorm skill's detach-awareness check succeeds (not silently fails) when `spex-detach` is enabled and `archive.path` is configured.
- **SC-003**: The archive operation in detach mode results in all three artifact directories present in the sibling specs repo and absent from the code fork.
- **SC-004**: Post-detach verification catches 100% of SpecKit artifact leaks in the PR diff (zero false negatives for configured strip_paths).
- **SC-005**: The fork detection warning fires when `.gitignore` is missing SpecKit paths and an `upstream` remote exists.
- **SC-006**: The brainstorm skill's revisit detection includes documents from the sibling specs repo's `brainstorm/` directory when `archive.path` is configured.
- **SC-007**: Running `specify init` with `spex-detach` enabled in a directory with a sibling `*-specs` directory suggests it as the default `archive.path`.

## Smoke Test

1. Set up a test project with `spex-detach` enabled and a sibling `*-specs` directory configured as `archive.path`. Create some spec artifacts, then run `spex-finish` and verify the `pr/<branch>` branch is clean and the sibling repo received the archived artifacts.
2. Intentionally place a spec-like file outside the configured `strip_paths` and run detach. Verify the post-detach verification catches the leak and reports the file path.
3. Run the brainstorm skill in a project with `spex-detach` enabled and `archive.path` set. Verify the brainstorm document is created in the sibling specs repo (not locally).

## Clarifications

### Session 2026-07-14

No critical ambiguities detected. All open questions were resolved during brainstorming (Brainstorm #37, revisit 2026-07-14):

- Archive behavior: default-on during detach, skippable with `--skip-archive`
- Verification scope: `git diff` against merge base (not `git ls-tree`)
- Brainstorm archiving: included alongside `specs/` and `.specify/`
- Binary file handling: accepted as known limitation
- Init auto-detection: scan sibling `*-specs` directories, suggest as default

Coverage summary: all taxonomy categories assessed as Clear. Spec is ready for planning.

## Assumptions

- The sibling specs repo is a regular git repository that the user has write access to.
- The `archive.path` in `spex-detach-config.yml` is a relative or absolute path to the sibling specs repo root.
- Text files are the dominant artifact type in upstream contributions. Binary file handling via `git apply --index` with `--binary` is a known limitation accepted during brainstorming.
- The `spex-finish` command's phase structure (Phase 1-4) remains stable and the detach integration can hook into the existing flow after Phase 2.
- The brainstorm skill's detach-awareness code path already exists and only needs the script path corrected (not a new implementation).
