# Review Guide: Post-Specify Worktree Creation

**Branch**: `015-worktree-post-specify` | **Date**: 2026-04-06

## What This Feature Does

Updates the worktrees trait so that after `speckit.specify` completes, a git worktree is created using the `<repo-name>:<branch-name>` naming convention (e.g., `cc-spex:015-feature`), with all modified tracked files committed before switching to `main`.

## Key Review Areas

### 1. Colon Naming Convention (FR-003)
**File**: `spex/skills/worktree/SKILL.md` (Step 4)
**What to check**: Path computation derives `REPO_NAME` from `basename $(git rev-parse --show-toplevel)` and constructs `<base>/<repo>:<branch>`. Verify the path resolution handles relative `..` correctly.

### 2. Commit Scope (FR-001)
**File**: `spex/skills/worktree/SKILL.md` (Step 5)
**What to check**: Changed from `git add "$SPEC_DIR"` to `git add -A`. Verify there's a `git diff --cached --quiet` guard to skip empty commits. Confirm `.claude/skills/` is in `.gitignore` so regenerated files aren't committed.

### 3. Trait Overlay Ordering
**File**: `spex/overlays/worktrees/skills/speckit-specify/SKILL.append.md`
**What to check**: Overlay delegates to `{Skill: spex:worktree}` and stays under 30 lines. Superpowers overlay should be appended before worktrees overlay (determined by trait order in `spex-traits.json`).

### 4. Worktree Detection (FR-005)
**File**: `spex/skills/worktree/SKILL.md` (Step 3)
**What to check**: Correctly identifies when running inside a worktree (`.git` is a file) and skips creation. No changes expected here, but verify it still works with the new path format.

### 5. Listing Output (FR-007)
**File**: `spex/skills/worktree/SKILL.md` (List action)
**What to check**: Output shows colon-format paths consistent with the new naming convention.

## Spec Artifacts

| File | Purpose |
|------|---------|
| `spec.md` | Feature specification with 12 FRs, 4 user stories, 6 edge cases |
| `plan.md` | Implementation plan with technical context and project structure |
| `research.md` | 5 research decisions (naming, commit scope, ordering, detection, gap analysis) |
| `data-model.md` | Entity definitions and state transition diagram |
| `tasks.md` | 11 tasks across 5 phases, organized by user story |
| `quickstart.md` | Implementation quick reference |

## Supersedes

This feature supersedes `007-worktrees-trait` for the worktree creation flow. Listing and cleanup behaviors are carried forward with updates for the new naming convention.

---

## Code Review Guide (30 minutes)

> This section guides a code reviewer through the implementation changes,
> focusing on high-level questions that need human judgment.

**Changed files:** 3 source files (`spex/skills/worktree/SKILL.md`, `.gitignore`, `tests/test_marketplace_install.sh`)

### Understanding the changes (8 min)

- Start with `spex/skills/worktree/SKILL.md`: This is the core deliverable. Read Steps 4-8 of the Create action, which implement the colon naming, scoped commit, default branch detection, and switch instructions.
- Then `.gitignore`: Single line added (`.claude/skills/`) to ensure skills are regenerated per session in worktrees.
- Question: Does the overall Create flow (commit, checkout default branch, worktree add) handle all failure modes cleanly, or can any step leave the repo in an inconsistent state?

### Key decisions that need your eyes (12 min)

**Scoped commit strategy** (`spex/skills/worktree/SKILL.md` Step 5, relates to [FR-001](spec.md))

Changed from `git add -A` to `git add -u` + explicit `git add specs/$BRANCH_NAME .specify/`. This prevents staging unintended files while capturing new spec artifacts.
- Question: Are there other directories that `speckit-specify` might create that need explicit staging?

**Dynamic default branch detection** (`spex/skills/worktree/SKILL.md` Step 6)

Uses `git symbolic-ref refs/remotes/origin/HEAD` with fallback to `main`. This avoids hardcoding `main` for repos using `master` or other defaults.
- Question: Is the `refs/remotes/origin/HEAD` approach reliable enough, or should we also support a config option in `spex-traits.json`?

**Absolute base_path handling** (`spex/skills/worktree/SKILL.md` Step 4)

Added conditional to handle absolute vs relative `base_path` values from config.
- Question: Should we validate that the resolved path is "reasonable" (e.g., not traversing far outside the project), or is trusting the user's config sufficient?

### Areas where I'm less certain (5 min)

- `spex/skills/worktree/SKILL.md` Step 3 ([FR-005](spec.md)): The worktree detection compares `git rev-parse --git-dir` output, which may return relative paths when cwd is a subdirectory. This could cause false positives. Using `--absolute-git-dir` might be safer.
- `spex/skills/worktree/SKILL.md` Step 5: The `git add -u` + explicit paths approach assumes `speckit-specify` only creates artifacts in `specs/` and `.specify/`. If future features add other output directories, this would need updating.

### Deviations and risks (5 min)

- The Step 5 commit strategy deviates from the original [research R2](research.md) recommendation of `git add -A`. The change was driven by deep review findings about staging unintended files. Question: "Is the narrower staging scope acceptable given R2's rationale about brittleness?"
- No other deviations from [plan.md](plan.md) were identified.

---

## Deep Review Report

> Automated multi-perspective code review results. This section summarizes
> what was checked, what was found, and what remains for human review.

**Date:** 2026-04-07 | **Rounds:** 2 (R1 + R2) | **Gate:** PASS

### Review Agents (R2, post-separator change)

| Agent | Findings | Status |
|-------|----------|--------|
| Correctness | 4 | completed |
| Architecture & Idioms | 5 | completed |
| Security | 4 | completed |
| Production Readiness | 6 | completed |
| Test Quality | 3 | completed |
| CodeRabbit (external) | 0 | completed |
| Copilot (external) | 0 | skipped (not installed) |

### Findings Summary (cumulative)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 12 | 12 | 0 |
| Minor | 17 | 2 | 15 |

### What was fixed automatically

**R1 (8 Important):** Replaced `git add -A` with scoped staging, added explicit control flow halts to all guard clauses, added base_path validation for empty results and absolute paths, removed duplicate `git worktree add` command, replaced hardcoded `main` with dynamic default branch detection, updated switch instructions to use computed path, added `worktree`/`worktrees` to integration test arrays.

**R2 (4 Important):** Added WSL + NTFS detection for repos on Windows filesystems via `/mnt/c/` (production agent), added worktree-inside-repo check for misconfigured `base_path` (production agent), strengthened default branch fallback chain with `main`/`master` probing (production agent), added existence guards before `git add specs/$BRANCH_NAME` (correctness/production agents).

### What still needs human attention

All Critical and Important findings were resolved. 15 Minor findings remain (see [review-findings.md](review-findings.md) for details). Reviewers may want to check:

- The worktree detection comparison at Step 3 may produce false positives with relative git-dir paths. Is `--absolute-git-dir` worth adopting?
- Default branch detection is duplicated between Create and Cleanup. Consider extracting to a shared utility section.
- The `git add -u` in Step 5 stages all tracked modifications per FR-001. This is by design (ensures clean checkout) but means WIP changes get committed under the spec commit message.

### Recommendation

All findings addressed. Code is ready for human review with no known blockers.
