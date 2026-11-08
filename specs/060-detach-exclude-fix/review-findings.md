# Deep Review Findings

**Date:** 2026-11-03
**Branch:** 060-detach-exclude-fix
**Rounds:** 3 fix rounds (round 3 applied the user's decisions on the remaining findings; final re-reviews clean)
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 11 | 10 | 0 |
| Minor | 24 | 20 | 5 |
| Notable | 1 | - | 1 |
| **Total** | **36** | **30** | **6** |

One Important finding (FINDING-4, Codex) was reclassified to Minor as an ambiguous requirement interpretation; it is counted in the Minor "Remaining" column (won't fix, user decision). The other remaining Minor findings are R2 and R8 (accepted, user decision) and R3 and R4 (deferred).

**Agents completed:** 5/6 (Goal Alignment skipped: no PR found) + 2 external tools (CodeRabbit, Codex); Copilot disabled in config.
**Agents failed:** none. CodeRabbit first failed on an unsupported `--files` flag and was re-run with `--base main --committed`.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/setup.yml (apply-extensions vs configure-git-exclude); spex/scripts/spex-init.sh (do_init, fast path)
- **Category:** correctness
- **Source:** codex (also reported by: architecture-agent, correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `ensure` (write and verify) ran inside apply-extensions, before `configure-git-exclude` appended spex's own block (`**/.specify/**`, `!**/.specify/spex.json`, `!**/.specify/memory/constitution.md`). The verification therefore checked an exclude file that was not final.

**Why this matters:** With a glob entry such as `.specify/**`, setup printed `Stealth mode: active` and the next step re-included spex.json and the constitution (SC-002 violation). Default `.specify/` is not affected because git does not descend into an excluded directory.

**How it was resolved:** `configure-git-exclude` now runs before `apply-extensions` in setup.yml, and `configure_git_exclude` runs before `install_extensions` in both do_init branches and the legacy fast path. A workflow regression test asserts that an active report with a `.specify/**` entry matches the final rules (`git check-ignore` on spex.json, constitution, specs).

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-detach-config.sh (save)
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: codex)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `save` always copied the live config over an existing saved copy. After a run that installed the template but never restored (interrupt, failed restore), the next run overwrote the user's saved configuration with the template.

**Why this matters:** Silent loss of archive path and exclude paths (FR-007, SC-003), triggered by the natural next step (re-running setup).

**How it was resolved:** `save` keeps an existing regular saved copy when the live config is byte-identical to `config-template.yml` and the saved copy differs, and says so. Tests cover the retry and the "edited config replaces an older copy" case; the workflow test asserts the installed config equals the template.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py (synthesize)
- **Category:** correctness
- **Source:** codex (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in round 2)

**What is wrong:** Bracket classes produced probes that did not match the glob (`[!a-z]` gave `x`), POSIX classes were mangled, and `[!xyzq0]` raised an uncaught `StopIteration`.

**Why this matters:** FR-002 requires a probe that matches the glob; the result was false warnings or a crash after entries were written.

**How it was resolved:** `bracket_end` finds the closing bracket (leading `]`, `!`/`^`, POSIX classes), `bracket_char` picks the first candidate that fnmatch accepts (POSIX classes expanded, upper case and space tried late for `core.ignorecase`), then any printable ASCII character. Verified against `git check-ignore` for 13 patterns; covered in tests/test_spex_detach.sh.

### FINDING-4
- **Severity:** Minor (reclassified from Important, ambiguous)
- **Confidence:** 70
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py:is_tracked
- **Category:** correctness
- **Source:** codex
- **Round found:** 1
- **Resolution:** won't fix (user decision)

**What is wrong:** Unanchored entries (`specs/`, `CLAUDE.md`) match at any depth in gitignore, but the tracked check only looks at the root-relative path, so tracked files in `nested/specs/` are not reported.

**Why this matters:** A nested tracked file stays visible while stealth mode is reported active.

**How it was resolved:** Not changed, by user decision. Forked upstream projects often track nested `specs/` directories of their own, which would turn into a permanent warning the user cannot clear, and spex only writes its artifacts at the root paths. The reason is documented in a comment at `is_tracked`.

### FINDING-5
- **Severity:** Important
- **Confidence:** 92
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py (PROBE_NAME)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The directory probe was a dotfile (`.spex-detach-probe`). Any `.*` rule (global excludes file, upstream .gitignore) made it ignored, so verify reported active with no detach entries at all.

**Why this matters:** False "Stealth mode: active" (SC-002, FR-004), the exact leak the feature prevents.

**How it was resolved:** Probe renamed to `spex-detach-probe`. Regression test with `core.excludesFile` containing `.*` (fails on the old code, passes now).

### FINDING-6
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py (read_exclude_paths)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** An existing but unreadable config (yq missing, invalid YAML) silently fell back to the defaults, so custom exclude paths were dropped without notice.

**Why this matters:** Custom paths can be re-exposed while verification reports active for the defaults.

**How it was resolved:** The fallback stays (spec edge case), but ensure and verify now print `Stealth mode: cannot read <config> (<reason>); using the default exclude paths` once. The line passes the fast-path filter and the skill relay rules. Documented in README and help.md; tested.

### FINDING-7
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/codex/skills/cc-spex-init/SKILL.md (Report)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The Codex init skill had no instruction to relay stealth-mode lines, unlike the Claude init skill.

**Why this matters:** FR-003/FR-004/FR-010 require the result to reach the user; a Codex agent could drop the warning.

**How it was resolved:** Added the same relay paragraph to the Codex skill's Report section.

### FINDING-8
- **Severity:** Important
- **Confidence:** 88
- **File:** tests/test_workflow_setup.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The workflow test did not isolate git from the developer's global excludes file, which on this machine contains `**/.specify/**`. The spex.json/constitution assertions could pass for the wrong reason.

**How it was resolved:** Exports `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and `core.excludesFile=/dev/null` via `GIT_CONFIG_COUNT`; asserts each entry is in the local exclude file exactly once.

### FINDING-9
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/extensions/spex-detach/scripts/spex-detach.py (bracket_char)
- **Category:** correctness
- **Source:** codex (re-review round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** Classes like `[.]` or `[]]` matched no candidate and fell back to `x`, which could verify the wrong filename.

**How it was resolved:** After the preferred candidates, every printable ASCII character except `/` is tried. Tested.

### FINDING-10
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/scripts/spex-detach-config.sh (save)
- **Category:** correctness
- **Source:** codex (re-review round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The round-1 symlink hardening (`rm -f "$SAVED"` before `cp`) deleted an existing recovery copy when the copy then failed.

**How it was resolved:** The copy is staged in a `mktemp` file in `.specify/` and moved into place; a failure leaves the previous saved copy untouched and a symlink is replaced, never written through. Tested (unreadable config keeps the earlier copy, no staging file left).

### Fixed Minor findings

- **spex/scripts/spex-detach-config.sh** (security): `save` wrote through a symlink at the fixed saved-copy name and `restore` moved a symlink into the config path. Fixed (staged copy; restore refuses a symlink). Tested.
- **spex/extensions/spex-detach/scripts/spex-detach.py run_enable** (security): `git ls-files` without `--`. Fixed.
- **spex-detach.py** (architecture): unused `args` parameter in `run_enable` and unreachable `None` checks in `cmd_ensure`. Removed.
- **spex/scripts/spex-init.sh run_detach_enable** (architecture): comment claimed a precondition the function does not check. Comment rewritten (function name kept).
- **spex/scripts/spex-init.sh install_extensions, spex/setup.yml install-ext-spex-detach** (correctness): a failed restore left spex-detach enabled. spex-init.sh disables it before `exit 1`; setup.yml disables before restoring. Tested in tests/test_init_detach.sh.
- **spex/setup.yml install-ext-spex-detach** (correctness): a failed `specify extension add` was swallowed and the restore consumed the saved copy. Now `add || exit 1`.
- **spex-detach.py POSIX_CLASSES** (re-review): `punct` expansion ended in `-` (range) and `graph`/`print` were subsets. Fixed and tested.
- **spex/scripts/spex-init.sh fast path** (re-review): after a failed restore in the quiet install and a successful visible retry, init printed READY although the declaration was never applied. Now exits 1 with a clear error.

## Round 3: user decisions on the remaining findings

| # | Finding | Resolution |
|---|---------|------------|
| R1 | Tracked check root-only for unanchored entries (FINDING-4) | won't fix (user decision); comment at `is_tracked` |
| R2 | Stale `.specify/.spex-detach-was-enabled` marker can mislabel a later Codex setup run as "Repaired" | accepted (user decision): needs an interrupted run plus an unusual follow-up; worst case is a wrong label |
| R3 | "ensure already ran" derived twice in spex-init.sh | deferred: moving the ensure call into install_extensions on every path is not cheap or low-risk in this PR |
| R4 | Fast-path awk filter keyed on message text | deferred: needs a message-format change across spex-detach.py, both skills and docs |
| R5 | Enable and verify normalized entries differently | fixed: `configured_entries()` shared by enable, verify and disable |
| R6 | Fast-path retry hard-coded the saved-copy path | fixed: `spex-detach-config.sh pending` via the `detach_config` helper |
| R7 | A failing `ensure` printed no stealth-mode line | fixed: WARNING block with exit code and last error line in spex-apply-extensions.sh and spex-init.sh; exit code unchanged |
| R8 | Stale saved copy can return after the user deletes the config | accepted (user decision): needs an interrupted run plus an unusual follow-up; worst case is an earlier saved config returning |
| R9 | Before-snapshot repair-vs-written decision untested | fixed: two apply-extensions cases with a disabled live registry |
| R10 | `--update`, marker creation, legacy fast path untested | fixed: tests/test_init_detach.sh |
| R11 | Workflow save failure untested | fixed: unreadable config as the failure injection (a read-only `.specify/` would also break the engine's run state) |
| R12 | No linked-worktree test | fixed: tests/test_spex_detach.sh |
| R13 | Disable-before-restore and `add || exit 1` untested | fixed: workflow tests with a specify wrapper |
| R14 | `run_detach_enable` name | fixed: renamed `run_detach_ensure` |

### New findings in round 3

- **Important, fixed:** spex/setup.yml install-ext-spex-detach and spex/scripts/spex-init.sh install_extensions. The new restore-failure workflow test showed that a failed restore which always disabled spex-detach made the next refresh's legacy migration (FR-023) drop spex-detach from the declaration. A failed restore now leaves spex-detach in its pre-run state: it is re-enabled from `.registry.before` in the workflow, or left enabled when `detach_before` was true in spex-init.sh. A failed run still never switches a disabled spex-detach on. Covered in both suites.
- **Minor, fixed (re-review):** the round-3 normalizer stripped leading whitespace from exclude lines, but git treats ` specs/` as a different pattern. Exclude lines are now compared after stripping trailing whitespace only, in enable and disable. Tested.
- **Minor, fixed (re-review):** on the legacy fast path, the failure warning said "see the error above", but the awk filter had removed that error. The warning now carries the last error line itself. Tested via spex-init.sh and spex-apply-extensions.sh.
- **Minor, fixed (re-review):** the normalizer and the crash heuristic had no discriminating tests. Added tests for whitespace, comment and duplicate entries, nested versus root tracked files, a visible-path exit 1 and a not-a-repository exit 2 without the failure warning, and a crash through `--refresh`.
- Codex re-review of round 3: no findings.

## Notable Observations

### NOTABLE-1
- **File:** Makefile (release target), .github/workflows/test.yml
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** `test-detach`, `test-apply-extensions` and `test-workflow-setup` are not part of `release` or CI.
- **Rationale:** Regressions in the leak fix could ship unnoticed. Pre-existing pattern.

## Post-Fix Spec Coverage

Fix rounds removed code only in spex-detach.py (redundant checks, old bracket logic) and spex-detach-config.sh (direct `cp`). All FR-001 to FR-014 remain implemented; see REVIEW-CODE.md. All spec requirements verified after fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test-detach test-apply-extensions test-worktree sync-scripts-check test-workflow-setup | 0 | 0 | passed |
| 1 | same + test-codex-plugin | 2 then 0 | 0 code failures | a stray `__pycache__` from a reviewer probe broke one `cp`; removed, rerun passed |
| 2 | make test-detach test-apply-extensions test-worktree sync-scripts-check test-workflow-setup test-codex-plugin | 0 | 0 | passed (96 + 37 + 40 + 129 + 364 + 54 + workflow 18 cases + 94; scripts in sync) |
| 3 | make test-detach test-apply-extensions test-worktree sync-scripts-check test-workflow-setup test-codex-plugin | 0 | 0 | passed (114 + 44 + 77 + 145 + 364 + 54 + workflow 22 cases + 94; scripts in sync) |

## Remaining Findings

All Minor: R1 (won't fix, user decision), R2 and R8 (accepted, user decision), R3 and R4 (deferred). See REVIEW-CODE.md "Remaining Findings" for details.
