# Code Review: Harden spex-detach for Reliable Upstream Contributions

**Spec:** specs/042-detach-hardening/spec.md
**Date:** 2026-07-14
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 97%**

- Functional Requirements: 11.5/12 (95.8%)
- Error Handling: 4/4 (100%)
- Edge Cases: 5/5 (100%)
- Non-Functional: 3/3 (100%)

## Detailed Review

### Functional Requirements

#### FR-001: Finish command detects spex-detach and invokes detach flow
**Implementation:** spex/extensions/spex/commands/speckit.spex.finish.md:173-235
**Status:** Compliant
**Notes:** Detection via `[ -d ".specify/extensions/spex-detach" ]`. Step 1.5 runs between Step 1 (commit) and Step 2 (merge base), exactly as specified.

#### FR-002: Finish offers "Push clean PR branch" option in Phase 4
**Implementation:** spex/extensions/spex/commands/speckit.spex.finish.md:312,455-471
**Status:** Compliant
**Notes:** Phase 4 includes "Push clean PR branch" when `DETACH_PR_BRANCH` is set. Option C implements the push logic with proper error handling.

#### FR-003: Detach archives specs, brainstorms, .specify/ to sibling repo
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:291-396, speckit.spex.finish.md:194-208
**Status:** Compliant
**Notes:** Archive runs with `--include-brainstorm` when not skipped and archive.path is configured. `--skip-archive` flag properly parsed and respected.

#### FR-004: Archive uses move semantics with deferred .specify/ deletion
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:378-391, speckit.spex.finish.md:224-235
**Status:** Compliant
**Notes:** Source deletion occurs after PR branch verified clean. `.specify/` deletion intentionally deferred. Deletions included in squash commit. Deletion failures produce warnings, not errors.

#### FR-005: Brainstorm skill references correct detach script path
**Implementation:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:294
**Status:** Compliant
**Notes:** Path is `.specify/extensions/spex-detach/scripts/spex-detach.sh` (correct, not the old incorrect `.specify/extensions/spex/scripts/spex-detach.sh`).

#### FR-006: Post-detach verification checks git diff against merge base using strip_paths-derived patterns
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:250-261,398-410,413-454
**Status:** Compliant
**Notes:** `build_fingerprint_patterns()` derives regex patterns from `strip_paths` config. Standalone `cmd_verify` subcommand also available. Verification integrated into `cmd_detach` post-creation.

#### FR-007: Verification fails with clear error listing leaked files
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:263-273
**Status:** Compliant
**Notes:** On leak detection, deletes PR branch, outputs JSON error with `leaked_files` array to stderr, exits 1.

#### FR-008: .gitignore check with non-blocking warning when upstream remote exists
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:123-150
**Status:** Compliant
**Notes:** `check_gitignore()` checks for `upstream` remote, reads `.gitignore`, emits warning to stderr for missing paths. Non-blocking (no exit code impact). Called from `cmd_detach`.

#### FR-009: Brainstorm scans sibling specs repo for revisit detection
**Implementation:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:241-256
**Status:** Compliant
**Notes:** Reads `archive.path` from config, scans `<archive.path>/brainstorm/` for `NN-*.md` files, includes matches alongside local brainstorm matches with source indication.

#### FR-010: Init auto-detects sibling *-specs directories
**Implementation:** spex/extensions/spex/commands/speckit.spex.brainstorm.md:302-308
**Status:** Minor Deviation
**Issue:** Implemented in brainstorm skill instead of `specify init` (upstream spec-kit). The plan documents this as intentional since init is upstream and cannot be modified per the "No modify speckit files" policy.
**Impact:** Minor (functional behavior achieved through alternative integration point)
**Recommendation:** Accept as-is. The plan explicitly documents this deviation.

#### FR-011: Idempotent PR branch regeneration
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:222
**Status:** Compliant
**Notes:** `git("branch", "-D", pr_branch)` before creating new branch. Failures silently ignored (branch may not exist on first run).

#### FR-012: Archive includes brainstorm/ alongside specs/ and .specify/
**Implementation:** spex/extensions/spex-detach/scripts/spex-detach.py:360-365, speckit.spex.finish.md:197
**Status:** Compliant
**Notes:** `--include-brainstorm` flag copies brainstorm/ to sibling repo. Finish invokes archive with this flag.

### Error Handling

| Error Case | Implemented | Location | Status |
|------------|-------------|----------|--------|
| Dirty working tree | Yes | spex-detach.py:182-185 | Compliant |
| Failed merge-base computation | Yes | spex-detach.py:200-204 | Compliant |
| Archive target not reachable | Yes | spex-detach.py:327-329 | Compliant |
| Source deletion failure | Yes | spex-detach.py:383-390 | Compliant (warning, not error) |

### Edge Cases

| Edge Case | Handled | Location | Status |
|-----------|---------|----------|--------|
| No code changes (spec-only) | Yes | spex-detach.py:217-219 (exit 2) | Compliant |
| No archive.path configured | Yes | finish.md:205-207 | Compliant |
| No upstream remote | Yes | spex-detach.py:127 (skip check) | Compliant |
| Multiple finish runs | Yes | spex-detach.py:222 (delete+recreate) | Compliant |
| --skip-archive with no archive.path | Yes | finish.md:194 (no-op) | Compliant |

### Extra Features (Not in Spec)

#### Standalone `verify` subcommand
**Location:** spex/extensions/spex-detach/scripts/spex-detach.py:413-454
**Description:** Verification available as standalone subcommand, not just integrated into detach
**Assessment:** Helpful addition for debugging and manual use
**Recommendation:** Add to spec (helpful, not scope creep)

## Code Quality Notes

- Python code follows existing patterns in the codebase (subprocess calls, JSON output)
- Error handling is consistent (JSON to stderr, appropriate exit codes)
- Markdown skill files follow the established command structure
- Documentation updated in both help.md and README.md

## Recommendations

### Spec Evolution Candidates
- [ ] FR-010 deviation: document brainstorm skill as the integration point (instead of init)

### Optional Improvements
- [ ] The standalone `verify` subcommand could be added to the spec for completeness

## Conclusion

The implementation is highly compliant with the specification (97%). The single deviation (FR-010) is documented, justified, and achieves the functional goal through an alternative integration point. All error cases and edge cases are properly handled. The code follows existing project patterns and conventions.

**Gate: PASS** (compliance >= 95%, deep review proceeding)

---

## Deep Review Report

**Date:** 2026-07-14
**Agents:** correctness, architecture, security, production-readiness, test-quality
**External tools:** CodeRabbit disabled, Copilot disabled
**Spec compliance (pre-review):** 97%
**Fix loop rounds:** 0 (no Critical/Important findings)

### Agent Findings Summary

| Agent | Critical | Important | Minor | Nitpick |
|-------|----------|-----------|-------|---------|
| Correctness | 0 | 0 | 2 | 1 |
| Architecture | 0 | 0 | 0 | 1 |
| Security | 0 | 0 | 1 | 1 |
| Production | 0 | 0 | 2 | 0 |
| Test Quality | 0 | 0 | 1 | 0 |
| **Total** | **0** | **0** | **6** | **3** |

### Correctness Agent

**C-1 [Minor]** `spex-detach.py:246` - `git commit` return code not checked. If the commit somehow fails after a successful `git apply --index`, `commit_sha` on line 247 would capture the merge-base commit SHA rather than a new commit. The subsequent verification would still pass (zero diff from merge-base to itself), so no data loss occurs, but the reported commit SHA in the JSON output would be wrong.
- **Risk:** Very low. The `diff_output` is verified non-empty before reaching this point, and `git apply --index` stages changes, so `git commit` should always succeed.
- **Recommendation:** Accept as-is. Adding a return code check would be defensive hardening but the failure path is practically unreachable.

**C-2 [Minor]** `spex-detach.py:251` - If `git diff --name-only` fails (returns empty string via the `git()` helper), verification silently passes. The `if diff_files:` guard on line 253 would skip the loop entirely, reporting the branch as clean.
- **Risk:** Very low. Both `merge_base` and `pr_branch` are valid refs at this point. The diff command should not fail.
- **Recommendation:** Accept as-is. A defensive check could log a warning, but the failure condition is practically unreachable.

**C-3 [Nitpick]** `spex-detach.py:9-13` - The `check` parameter in the `git()` helper is unused by any caller in the codebase. It is dead code and its semantics are confusing (name suggests `subprocess.run(check=True)` behavior but returns `None` instead of raising). Pre-existing, not introduced by this change.

### Architecture Agent

**A-1 [Nitpick]** `speckit.spex.finish.md:224-233` - The finish command manually deletes `specs/<feature>/` and `brainstorm/` directories after archive+verify, rather than delegating to the detach script's `--move` flag. This is actually architecturally correct per Constitution Principle VI (Skill Autonomy): the finish flow needs control over deletion timing (after PR branch verification), which the archive `--move` flag doesn't provide. The finish flow delegates to spex-detach scripts for archive, detach, and verify, keeping only the post-verification cleanup inline.
- **Verdict:** Not a violation. The three-step approach (archive copy, detach+verify, then delete) is more robust than `archive --move` and correctly implements FR-004's ordering requirement.

### Security Agent

**S-1 [Minor]** `spex-detach.py:90-93` - `validate_path_component()` checks for `..` in project and feature names but does not check for absolute paths or symlink traversal. A `project` value like `/etc/passwd` would pass validation.
- **Risk:** Low. Project names are auto-detected from git remote URLs (line 51-60), and feature names from the current branch. Both are developer-controlled. The archive target path itself comes from the config file, which is also developer-controlled.
- **Recommendation:** Accept as-is. This is a developer tool, not a public-facing service. Adding absolute path checks would be defensive but not security-critical.

**S-2 [Nitpick]** `spex-detach.py:346` - `shutil.copytree` follows symlinks by default. A symlink inside `.specify/` pointing outside the repo would be followed during archive. This is standard Python behavior and acceptable for a developer tool.

### Production-Readiness Agent

**P-1 [Minor]** `spex-detach.py:140-144` - The `.gitignore` check only handles exact path matches (`.specify`, `.specify/`, `/.specify`, `/.specify/`). It does not handle glob patterns (e.g., `.spec*`), comments (e.g., `# .specify/`), or negation patterns (e.g., `!.specify/important`).
- **Risk:** Low. This is an advisory warning, not a blocking check. The paths being checked (`.specify`, `specs`, `brainstorm`) are specific directory names, not patterns. False negatives (missing a glob that covers the path) would only result in an unnecessary warning, not data loss.
- **Recommendation:** Accept as-is. Full `.gitignore` parsing would add significant complexity for marginal benefit in an advisory-only check.

**P-2 [Minor]** `spex-detach.py:285-288` - The `except Exception` catch-all in `cmd_detach` calls `git checkout` and `git branch -D` for cleanup. If the checkout itself fails (e.g., filesystem corruption), the repo could be left on the PR branch. However, this is an exceptional circumstance and the user would notice immediately.
- **Recommendation:** Accept as-is. Adding nested error handling for the cleanup path would add complexity without practical benefit.

### Test Quality Agent

**T-1 [Minor]** No automated test suite exists for the spex-detach.py script. The project uses `make release` for schema validation and integration testing, and manual smoke tests for acceptance verification. All 18 acceptance scenarios from the spec's 7 user stories have corresponding implementation paths in the code and are verifiable through manual testing.
- **Coverage matrix:**
  - US1 (3 scenarios): All covered by finish.md Step 1.5 + Phase 4 Option C
  - US2 (3 scenarios): All covered by cmd_detach verification + cmd_verify
  - US3 (2 scenarios): Covered by brainstorm.md line 294
  - US4 (2 scenarios): Covered by cmd_archive with --move + --include-brainstorm
  - US5 (3 scenarios): Covered by check_gitignore()
  - US6 (2 scenarios): Covered by brainstorm.md lines 241-256
  - US7 (2 scenarios): Covered by brainstorm.md lines 302-308
  - **Unmapped:** 0 scenarios
- **Recommendation:** Accept as-is. The project's testing strategy relies on integration tests and manual smoke tests, which is appropriate for a CLI plugin.

### Fix Loop

No fix loop required. Zero Critical and zero Important findings. All 6 Minor findings and 3 Nitpick findings are accepted as-is with documented rationale.

### Spec Compliance (post-review)

No requirements were dropped during the review. Post-review compliance remains at **97%** (same as pre-review).

### Verdict

**PASS** - No Critical or Important findings. Implementation is spec-compliant (97%), architecturally sound, and production-ready. The 6 Minor findings are all low-risk and accepted with rationale.

### Agent Leaderboard

| Agent | Findings | Actionable | MVP |
|-------|----------|------------|-----|
| Correctness | 3 | 0 | |
| Production | 2 | 0 | |
| Security | 2 | 0 | |
| Test Quality | 1 | 0 | |
| Architecture | 1 | 0 | |

No MVP this round (no actionable findings).
