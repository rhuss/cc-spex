# Deep Review Findings

**Date:** 2026-04-07
**Branch:** 015-worktree-post-specify
**Rounds:** 2 (R1: implement review, R2: post-separator review)
**Gate Outcome:** PASS
**Invocation:** superpowers

## Summary (cumulative across both rounds)

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 12 | 12 | 0 |
| Minor | 17 | 2 | 15 |
| **Total** | **13** | **9** | **4** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/skills/worktree/SKILL.md:96-103
- **Category:** security / production-readiness
- **Source:** production-agent (also reported by: security-agent, architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`git add -A` stages all untracked files, including potential secrets or unintended files not covered by `.gitignore`. The comment only mentioned `.claude/skills/` as safe, but did not account for other transient files.

**Why this matters:**
Running autonomously after `speckit-specify`, developers have no opportunity to review what gets staged. Scratch files, debug logs, or credential files could be silently committed to the feature branch.

**How it was resolved:**
Replaced `git add -A` with `git add -u` (tracked modifications only) plus explicit `git add specs/$BRANCH_NAME .specify/` for new spec artifacts. This matches FR-001's stated intent of committing "all modified tracked files" plus spec artifacts.

### FINDING-2
- **Severity:** Important
- **Confidence:** 88
- **File:** spex/skills/worktree/SKILL.md:62-91
- **Category:** production-readiness / correctness
- **Source:** production-agent (also reported by: correctness-agent, architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Guard clauses in Steps 3 and 4 (worktree detection, path exists check) printed warnings but had no explicit control flow halt. Claude could proceed to subsequent steps despite error conditions.

**Why this matters:**
Without explicit halt instructions, Claude might continue executing Steps 5-7 (commit, checkout, worktree add) even after detecting the repo is already a worktree or the target path exists.

**How it was resolved:**
Changed all guard clause comments to "Stop here. Do not proceed to subsequent steps." and added explicit prose after each guard: "Do not proceed to any subsequent Create steps."

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/skills/worktree/SKILL.md:79
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`RESOLVED_BASE=$(cd "$REPO_ROOT/$BASE_PATH" && pwd)` would leave `RESOLVED_BASE` empty if the directory does not exist, potentially creating a worktree at the filesystem root.

**Why this matters:**
An empty `RESOLVED_BASE` produces `WORKTREE_PATH="/${REPO_NAME}:${BRANCH_NAME}"`, causing `git worktree add` to create a directory at `/`.

**How it was resolved:**
Added an explicit check: if `RESOLVED_BASE` is empty after resolution, report a clear error and halt.

### FINDING-4
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/skills/worktree/SKILL.md:127-139
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 7 contained two `git worktree add` code blocks: one bare command and one with error handling. The bare command was effectively dead code.

**Why this matters:**
Claude might execute both blocks, running `git worktree add` twice (the second failing because the worktree already exists).

**How it was resolved:**
Removed the bare command, keeping only the guarded `if ! git worktree add ...` block.

### FINDING-5
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/skills/worktree/SKILL.md:79
- **Category:** production-readiness
- **Source:** production-agent (also reported by: security-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Path resolution assumed `BASE_PATH` is always relative. An absolute `base_path` in config would produce a nonsensical concatenation like `/home/user/project//opt/worktrees`.

**Why this matters:**
Users might reasonably configure `base_path` to an absolute path like `/tmp/worktrees`. The `cd` would fail silently.

**How it was resolved:**
Added conditional: if `BASE_PATH` starts with `/`, use it directly; otherwise prepend `REPO_ROOT`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 82
- **File:** spex/skills/worktree/SKILL.md:143-159
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
Step 8 hardcoded `../<repo-name>:<branch-name>` in the `cd` command, which is only correct when `base_path` is the default `..`.

**Why this matters:**
Custom `base_path` configurations would produce incorrect switch instructions.

**How it was resolved:**
Changed to use the actual `WORKTREE_PATH` variable computed in Step 4, which is always correct regardless of `base_path`.

### FINDING-7
- **Severity:** Important
- **Confidence:** 82
- **File:** spex/skills/worktree/SKILL.md:113
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`git checkout main` hardcoded the branch name `main`. Repositories using `master` or other default branch names would fail.

**Why this matters:**
The entire worktree creation flow would be blocked on repos not using `main`.

**How it was resolved:**
Added dynamic detection: `git symbolic-ref refs/remotes/origin/HEAD` with fallback to `main`. Applied to both Step 6 and the Cleanup action.

### FINDING-8
- **Severity:** Important
- **Confidence:** 95
- **File:** tests/test_marketplace_install.sh:216,291
- **Category:** test-quality
- **Source:** test-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `EXPECTED_SKILLS` and `EXPECTED_OVERLAYS` arrays in the integration test did not include `worktree` and `worktrees`, meaning `make release` would not detect a missing or broken worktree skill/overlay.

**Why this matters:**
The release gate (T010) was the automated verification step but had a blind spot for the core artifact of this feature.

**How it was resolved:**
Added `"worktree"` to `EXPECTED_SKILLS` and `"worktrees"` to `EXPECTED_OVERLAYS`. Tests now pass at 37/37.

### FINDING-9
- **Severity:** Minor
- **Confidence:** 90
- **File:** tests/test_marketplace_install.sh:291
- **Category:** test-quality
- **Source:** test-agent
- **Round found:** 1
- **Resolution:** fixed (round 1) (combined with FINDING-8)

### FINDING-10
- **Severity:** Minor
- **Confidence:** 78
- **File:** spex/skills/worktree/SKILL.md:1-5
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
Skill name is singular (`worktree`) while trait name is plural (`worktrees`). This is by design (traits are nouns, skills are commands) but undocumented.

**Why this matters:**
Could cause confusion for contributors searching for "worktrees" in skills.

### FINDING-11
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/skills/worktree/SKILL.md:60-68
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
`git rev-parse --git-dir` may return a relative path when cwd is a subdirectory, causing the worktree detection comparison to produce a false positive.

**Why this matters:**
Could incorrectly skip worktree creation on a normal repo when Claude runs from a subdirectory.

### FINDING-12
- **Severity:** Minor
- **Confidence:** 75
- **File:** spex/skills/worktree/SKILL.md:209-210
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1) (combined with FINDING-7)

### FINDING-13
- **Severity:** Minor
- **Confidence:** 72
- **File:** spex/skills/worktree/SKILL.md:100-101
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** remaining

**What is wrong:**
`$BRANCH_NAME` is interpolated into a commit message without explicit sanitization.

**Why this matters:**
Extremely low risk since git branch names are restricted and Step 2 validates the `NNN-feature-name` pattern.
