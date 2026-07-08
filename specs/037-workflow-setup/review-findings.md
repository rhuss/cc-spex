# Deep Review Findings

**Date:** 2026-07-07
**Branch:** 037-workflow-setup
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 2 | 2 | 0 |
| Important | 9 | 6 | 3 |
| Minor | 6 | 0 | 6 |
| Notable | 2 | - | 2 |
| **Total** | **19** | **8** | **11** |

**Agents completed:** 5/5 (+ 1 external tool)
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Critical
- **Confidence:** 90
- **File:** spex/setup.yml:119 (all install-ext-* steps)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
All 7 `install-ext-*` steps unconditionally used `specify extension add --dev`, which creates symlinks. When the source is a temp clone from GitHub, these symlinks point into an ephemeral temp directory that will be cleaned up by the OS, silently breaking all extensions.

**Why this matters:**
Users installing via the primary distribution path (`specify workflow run <url>`) would get extensions that break after the next tmp cleanup or reboot.

**How it was resolved:**
Added conditional `--dev` flag: symlinks are only used for local/persistent sources, not for temp clones. Detection uses the temp dir name pattern (`spex-setup-*`).

### FINDING-2
- **Severity:** Critical
- **Confidence:** 90
- **File:** spex/setup.yml:327
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `codex-hooks` step used `printf > .codex/hooks.json`, overwriting the entire file. User-added hooks would be silently lost, violating FR-006 (idempotency, preserve user settings).

**Why this matters:**
Any Codex user who customized hooks.json would lose their configuration on re-run.

**How it was resolved:**
Replaced printf with jq-based merge: existing hooks are preserved, spex hooks are identified by command pattern and replaced/added without affecting user hooks.

### FINDING-3
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/setup.yml:60-64, spex/setup.yml:490+
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
When `locate-source` cloned the repo to a temp directory, no cleanup step removed it after the workflow completed. The spec explicitly requires cleanup of temporary clones.

**How it was resolved:**
Added a `cleanup-source` step at the end of the workflow that detects temp clone paths and removes them. Also added cleanup on clone failure in locate-source itself.

### FINDING-4
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/setup.yml:35-47
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The version check required >= 0.7.4 (per error message) but only validated major.minor, not patch. Versions 0.7.0-0.7.3 would incorrectly pass.

**How it was resolved:**
Added patch-level extraction and comparison. Now correctly rejects 0.7.0-0.7.3 while accepting 0.7.4+.

### FINDING-5
- **Severity:** Important
- **Confidence:** 90
- **File:** Makefile:72-78
- **Category:** correctness
- **Source:** correctness-agent (also reported by: architecture-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The `release` target updated versions in marketplace.json, plugin.json, and spex/VERSION, but did NOT update setup.yml or bundle.yml. Released assets would contain stale version strings.

**How it was resolved:**
Added `sed` commands to update versions in setup.yml and bundle.yml, and added both files to `git add`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/setup.yml:72-83
- **Category:** security
- **Source:** security-agent (also reported by: coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
`inputs.integration` accepted any string without validation. Invalid values would silently fall through to the default harness case, producing a misconfigured installation without error.

**How it was resolved:**
Added allowlist validation (`auto|claude|codex|opencode`) with explicit error on invalid input. Also added `${AGENT:-claude}` fallback for empty detect-agent output.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/setup.yml:311-312
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
JSON was constructed via `printf` for statusline config when the settings file didn't exist, while the same code path used `jq` when the file existed. The printf path did not escape JSON-special characters in file paths.

**How it was resolved:**
Replaced `printf` with `jq -n` for consistent JSON construction.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/scripts/spex-init.sh:599
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The bootstrap `specify init` in spex-init.sh used `|| true` to swallow failures, leaving the workflow engine without a valid `.specify/` state.

**How it was resolved:**
Replaced `|| true` with explicit error handling that exits with an error message on bootstrap failure.

### FINDING-9
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/setup.yml:212-228, 230-243
- **Category:** correctness
- **Source:** coderabbit
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:**
The interactive extension selection prompt step dispatched to the agent but the fallback step never consumed the response or disabled any extensions. The prompt response was discarded.

**How it was resolved:**
Updated the fallback step to parse the prompt response and disable unselected extensions, matching the behavior of the explicit (comma-separated) path.

### FINDING-10
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/setup.yml, spex/scripts/spex-init.sh
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** remaining (architectural)

**What is wrong:**
setup.yml reimplements nearly every function from spex-init.sh. Both are live: setup.yml runs on default path, spex-init.sh functions serve `--refresh`, `--update`, and legacy fallback. Bug fixes must be applied in two places.

**Why this matters:**
The version requirement has already diverged (spex-init.sh requires >= 0.5.0, setup.yml >= 0.7.4). Future divergences are likely.

### FINDING-11
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/setup.yml:109-191, 290-310
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** remaining (design decision)

**What is wrong:**
Shell steps do not use `set -euo pipefail`. Intermediate command failures within multi-line shell blocks may be silently swallowed depending on the workflow engine's shell invocation mode.

**Why this matters:**
A `jq` failure in the permissions step could produce an empty temp file, and `mv` would replace settings with empty content.

### FINDING-12
- **Severity:** Important
- **Confidence:** 95
- **File:** tests/ (directory-level gap)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** remaining (requires test infrastructure)

**What is wrong:**
No automated tests exist for the workflow-based setup. All 6 test tasks (T016, T020, T024, T027, T030, T031) were manual verification only.

**Why this matters:**
Any future change to setup.yml has no automated regression detection. The existing `test_marketplace_install.sh` proves the project has the pattern for integration tests.

## Minor Findings

- **FINDING-13** (architecture): Dead code in spex-init.sh - `optional_extensions` array is empty, making the 28-line prompt loop unreachable
- **FINDING-14** (architecture): spex-init.sh pre-init hardcodes `--integration claude` before workflow's detect-agent runs
- **FINDING-15** (architecture): Version "6.0.0" duplicated across setup.yml and bundle.yml (3 locations), partially addressed by Makefile fix
- **FINDING-16** (test-quality): Spec says "disable dependents" when dependency removed, but implementation auto-enables dependency instead
- **FINDING-17** (test-quality): Extension reinstall (remove+add) contradicts FR-006 "skip already-installed"
- **FINDING-18** (test-quality): Codex/OpenCode permission steps are no-op stubs

## Notable Observations

### NOTABLE-1
- **File:** spex/setup.yml:109-191
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** 7 identical install-ext-* steps differ only in extension name
- **Rationale:** Acceptable in declarative YAML where each step is an independently trackable unit. Worth consolidating if the workflow engine adds a for-each construct.

### NOTABLE-2
- **File:** spex/setup.yml:72, 106, 229, 367
- **Category:** security
- **Source:** security-agent
- **Description:** Template expressions (`{{ inputs.* }}`) interpolated into shell commands are theoretically vulnerable to injection
- **Rationale:** Mitigated by inputs being self-targeting (user runs the workflow themselves) and by the input validation added in Fix 6. The workflow engine lacks an `env:` mechanism for safe variable passing.

## Test Suite Results

No test command detected; post-fix test step was skipped.

## Remaining Findings

3 Important findings remain, all architectural/process-level:

1. **Dual maintenance surface** (architecture-agent): setup.yml and spex-init.sh duplicate logic. Recommend having `--refresh` and `--update` also delegate to the workflow, and marking bash functions as legacy-only.
2. **Missing set -euo pipefail** (production-agent): Shell steps lack strict error handling. Adding it broadly risks breaking steps that rely on non-zero exits (e.g., grep). Recommend adding to critical steps (permissions, statusline) first.
3. **No automated tests** (test-quality-agent): Create `tests/test_setup_workflow.sh` covering extension install, selection, permissions, and idempotency.
