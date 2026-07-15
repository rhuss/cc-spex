# Research: Detach Hardening

## R1: Finish Command Integration Point

**Decision**: Insert detach logic between Phase 3 (Squash) and Phase 4 (Select Action) as a new Phase 3.5.

**Rationale**: The `before_finish` hook fires before Phase 1 (Smoke Test), which is too early because the branch hasn't been squashed yet. Detach needs the squashed branch to create a clean diff. The integration must be direct (inline in finish.md), not via the existing hook system.

**Alternatives considered**:
- Using `before_finish` hook: fires too early (before smoke test and squash)
- Using `after_finish` hook: fires after merge, too late to offer the clean branch as a push target
- Adding a new hook point between phases: over-engineering for a single extension integration

## R2: Archive Timing and .specify/ Availability

**Decision**: Archive copies files to sibling repo and commits there. Source deletion is deferred: `.specify/` stays on disk throughout finish so post-completion hooks work. Source files are cleaned up naturally when the feature branch is deleted or the worktree is removed.

**Rationale**: The review agent identified that deleting `.specify/` during archive would break post-completion hooks (e.g., `after_finish` flow-state cleanup). Since the detach creates a separate `pr/<branch>` from git history (not the working tree), the archive timing doesn't affect the clean branch.

**Alternatives considered**:
- Delete source immediately after archive: breaks hooks that read `.specify/`
- Stage deletion, commit during squash: overly complex, unnecessary since feature branch is transient

## R3: Verification Pattern in spex-detach.py

**Decision**: Add a `verify` subcommand to `spex-detach.py` that checks `git diff --name-only` on the PR branch against the merge base for SpecKit fingerprints. Integrate into `cmd_detach` as a post-creation step.

**Rationale**: Using `git diff --name-only` against the merge base checks only the PR's own changes (not upstream content). The fingerprint patterns derive from the configured `strip_paths` plus known SpecKit file patterns (spec.md, plan.md, tasks.md inside any `specs/` directory).

**Alternatives considered**:
- `git ls-tree`: checks all files on the branch, could false-positive on upstream content
- Separate verification command: adds another step to remember, better to integrate into detach

## R4: Move Semantics for Archive

**Decision**: Add a `--move` flag to `cmd_archive` in `spex-detach.py`. When set, delete source directories after successful copy and commit. The finish integration passes `--move` by default, skippable with `--skip-archive`.

**Rationale**: Move semantics ensure the sibling specs repo is the authoritative copy. Source deletion is safe because: (1) the archive committed successfully, (2) the feature branch is about to be deleted anyway, (3) `.specify/` deletion is deferred (only `specs/<feature>/` and `brainstorm/` are moved immediately).

## R5: Brainstorm Discovery from Sibling Repo

**Decision**: In the brainstorm skill's revisit detection (step 4), add a lookup for `<archive.path>/brainstorm/` alongside the local `brainstorm/` scan. Use the same keyword overlap logic for matching.

**Rationale**: The `archive.path` is already available via `spex-detach-config.yml`. Adding a second scan path is minimal code change in the brainstorm skill.

## R6: Init Auto-Detection for archive.path

**Decision**: This is a UX improvement in the brainstorm/init flow, not a code change to `specify init` itself. When the brainstorm skill or init hook detects `spex-detach` is enabled and `archive.path` is empty, it scans `../` for directories matching `*-specs` and suggests the first match.

**Rationale**: The `specify` CLI is upstream and can't be modified here. The auto-detection logic belongs in the spex-detach extension's init/setup flow or in the brainstorm skill when it first needs the path.
