# Review Guide: spex-detach Extension

**Generated**: 2026-06-26 | **Spec**: [spec.md](spec.md)

## Why This Change

Contributors who use spex to organize their work on upstream projects face a problem: upstream maintainers don't use SDD, and PRs containing `.specify/`, `specs/`, or `brainstorm/` directories will be rejected or confuse reviewers. Today there is no way to use spex's spec-driven workflow while producing clean PRs that contain only code changes. Contributors must either skip spex entirely or manually strip spec artifacts before submitting.

## What Changes

A new `spex-detach` extension is added that integrates into the existing `spex-finish` command. When enabled, finish creates a clean PR branch (`pr/<feature-branch>`) containing only code changes via a squash-onto-base mechanism. Spec artifacts are optionally archived to a separate project-specs repository for durable storage. The brainstorm command is modified to write documents to the project-specs repo instead of the code worktree when detach mode is active. No existing behavior changes when the extension is not installed.

## How It Works

The extension is structured as a standard spex extension bundle at `spex/extensions/spex-detach/` with a manifest, config template, and one command. Core git operations live in a shell script (`spex-detach.sh`) following the State as Scripts constitution principle.

**Clean branch creation (squash-onto-base)**: The script computes the merge-base between the feature branch and the upstream default branch, generates a filtered `git diff` excluding spec paths (`.specify`, `specs`, `brainstorm`), creates a new `pr/<branch>` from the merge-base, and applies the filtered diff as a single commit. This produces a branch where the upstream PR diff shows only code changes with no spec artifact traces in history.

**Finish command integration**: After Phase 2 (commit outstanding changes) in the existing finish flow, a detection block checks for the `spex-detach` extension. If found, it calls the detach script, then offers "Push clean PR branch to upstream" as the recommended action in Phase 4.

**Archiving**: A `before_finish` hook optionally copies `.specify/` and `specs/<feature>/` to a configured project-specs repo, organized by `<project-name>/<feature-name>/`. Project name is derived from git remotes (upstream > origin > directory name).

## When It Applies

**Applies when**:
- Contributing to upstream projects that do not use SDD
- The contributor wants spec-driven workflow benefits while producing clean upstream PRs
- Working across multiple features in parallel via git worktrees

**Does not apply when**:
- The project already uses SDD (standard single-repo mode is sufficient)
- Quick fixes or one-off contributions that don't benefit from spec-driven workflow
- Cross-project brainstorm linking is needed (deferred: manual management in v1)

## Key Decisions

1. **Squash-onto-base for clean branches** (not filter-branch or cherry-pick): `git diff` with pathspec exclusions is simpler, produces a single clean commit, and avoids history rewriting. filter-branch is overkill; cherry-pick doesn't support per-file exclusions.

2. **Modify finish command** (not create a wrapper): Keeps UX simple with one finish command. The extension detection is additive; existing behavior is unchanged when spex-detach is not installed. A wrapper would duplicate verification and cleanup logic.

3. **Shell script for core operations** (not inline bash in skill): Follows constitution principle VII (State as Scripts). Scripts are testable, deterministic, and don't get skipped after context compression.

4. **Extension bundle** (not built-in feature): Follows constitution principles II and III. Users who don't contribute to upstream projects never encounter this feature. Extensions are independently installable and composable.

5. **Archive both `.specify/` and `specs/`** (not just specs): Preserves the full design context including spec-kit configuration, flow state, and task tracking. This enables reconstructing the complete development history after the code worktree is deleted.

## Areas Needing Attention

- **Finish command modifications**: The finish command is already complex (~690 lines). Adding detach detection and modified action options increases its surface area. Reviewers should verify the new code paths don't interfere with existing worktree, autonomous mode, or watch mode behavior.

- **`git diff | git apply` with binary files**: The `--binary` flag is needed but may have edge cases with large binaries or unusual file modes. This should be tested with a repo containing binary assets.

- **Project name derivation**: The fallback chain (`upstream` remote > `origin` > directory name) may produce unexpected results for repos with non-standard remote names. The config override (`upstream.default_branch`) partially addresses this, but there's no override for project name itself.

- **Brainstorm redirection (US4)**: Modifying the brainstorm command to write to an external directory is a behavior change in a core command. The detection logic must be robust to avoid accidentally redirecting brainstorms in non-detach projects.

## Open Questions

No open questions identified. All ambiguities were resolved during the clarification phase (5 questions answered in Session 2026-06-25).

## Review Checklist

- [ ] Key decisions are justified
- [ ] Breaking changes are documented with migration guidance
- [ ] Scope matches the stated boundaries
- [ ] Success criteria are achievable
- [ ] No unstated assumptions
- [ ] Extension manifest follows established schema
- [ ] Shell script follows POSIX-compatible conventions
- [ ] Finish command modifications are gated on extension detection
- [ ] Clean branch verification (FR-008) prevents spec artifact leakage

---

<!-- Code phase sections are appended below this line by the phase-manager command -->
