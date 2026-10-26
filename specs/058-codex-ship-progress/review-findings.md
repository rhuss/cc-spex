# Deep Review Findings

**Date:** 2026-10-26
**Branch:** 058-codex-ship-progress
**Rounds:** 3
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 10 | 10 | 0 |
| Minor | 14 | 10 | 4 |
| Notable | 4 | - | 4 |
| **Total** | **28** | **20** | **8** |

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR found), plus 2 external tools (CodeRabbit, Codex). Copilot is disabled in the config.
**Agents failed:** none. The first CodeRabbit call failed (CLI 0.7.6 has no `--files` option); it was rerun with `--base main --committed`, and findings on spec artifacts were ignored.

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-codex-progress.py (write_atomic, cmd_apply)
- **Category:** correctness
- **Source:** correctness-agent (also reported by: security-agent, production-readiness-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `write_atomic` made the temp file next to `config.toml` and called `os.replace` on the unresolved path. When `~/.codex/config.toml` was a symlink, the link was replaced by a regular file and the real target was left unchanged.

**Why this matters:** Users who manage the file with stow, chezmoi or home-manager would see their managed config and the live file silently diverge.

**How it was resolved:** `cmd_apply` and `cmd_check` now resolve the real path (`real_path`) and read, write and take the mode from the link target. `APPLIED path=` still shows the user-facing path. New test: `test_symlinked_config_is_edited_through_the_link`.

**External tool analysis (CodeRabbit):**
> Update write_atomic to resolve path to its real filesystem target before creating the temporary file or checking file mode, so the atomic replacement updates the target and preserves any symlink.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-codex-progress.py (parse, cmd_check); spex/codex/skills/cc-spex-init/scripts/codex-progress.sh
- **Category:** production-readiness
- **Source:** production-readiness-agent (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** On Python 3.9 or 3.10 (stock macOS `/usr/bin/python3`), `tomllib` is missing. `check` printed `ASK` even when both lists already contained `task-progress` (breaking FR-018), and `apply` could never succeed. The snippet then suggested default lists, which would drop the user's own items.

**Why this matters:** On a common platform, users were asked on every init and always hit the failure path.

**How it was resolved:** `parse` falls back to `tomli`. Without any TOML parser, `check` prints `UNSUPPORTED`, and SKILL.md skips the question and shows the hint instead. The wrapper now prefers a Python 3.11+ interpreter. README documents the requirement. New test: `test_check_unsupported_without_toml_parser`.

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-codex-progress.py (snippet_text)
- **Category:** production-readiness
- **Source:** production-readiness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, refined in round 2)

**What is wrong:** The snippet always printed a `[tui]` header. SKILL.md shows it as "the lines to add" on the failure path, where the file usually already has a `[tui]` table. Pasting it created a duplicate table, and Codex could not load the file.

**Why this matters:** The manual fallback of FR-023 could produce a config that Codex rejects.

**How it was resolved:** With an existing `[tui]` header, the snippet prints a comment ("set these keys in your existing [tui] table") followed by the key lines. With no table, or only a subtable, it prints the `[tui]` header. When the file is unparseable or uses dotted or inline `tui` keys, it prints an "append task-progress" instruction and never suggests replacing the lists.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-setup-profile.py:111-113
- **Category:** external
- **Source:** codex
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** A non-string `codex_progress` value (array, object) raised an uncaught `TypeError` from the set-membership test instead of the validation error.

**Why this matters:** `load()` validates the stored profile, so a malformed `.specify/spex.json` crashed every setup command with a traceback.

**How it was resolved:** Values are type-checked before the membership test. The same guard was added for `harness` and `security` in round 2. Tests cover list and object values.

**External tool analysis (Codex):**
> When `.specify/spex.json` contains a non-string `codex_progress` value such as an array or object, this set-membership check raises an uncaught `TypeError` instead of returning the documented validation error.

### FINDING-5
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-ship-statusline.sh (render_ship, banner mode)
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, tightened in rounds 2 and 3)

**What is wrong:** `stage_index` and `total_stages` from the state file went straight into bash arithmetic, and bash evaluates `a[$(cmd)]` subscripts. The new `progress` command runs the banner after every state change in Codex and OpenCode, so this was a new trigger for command execution from a planted state file. Control characters in `stage` also reached the banner that the agent prints verbatim (FR-011).

**Why this matters:** A tampered `.specify/.spex-state` could run arbitrary commands in Codex and OpenCode sessions and inject text into the agent's reply.

**How it was resolved:** In banner mode only, the index and total must be decimal numbers of at most two digits with no leading zero, the index must not exceed the total, and the stage must match `[A-Za-z0-9_-]`. Otherwise no banner is printed, while the plan still is. The Claude status line output is unchanged (golden tests pass, and the adapted Claude command is byte-identical to main).

### FINDING-6
- **Severity:** Important
- **Confidence:** 80
- **File:** tests/test_adapt_ship_progress.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The "Claude output unchanged" test compared the new adapter with itself, so a regression from the `jq -r` to `jq -j` change in other token expansions would not be caught.

**Why this matters:** FR-016 and SC-003 (P1) were not really guarded.

**How it was resolved:** New fixture (a2) with a non-empty multi-line block token, an inline token and a missing token. It is compared to golden output that the pre-feature adapter produced (checked by running main's adapter on the same fixture).

### FINDING-7
- **Severity:** Important
- **Confidence:** 75
- **File:** tests/test_ship_state.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** No progress test went through `advance`. The done case used a hand-written fixture, so US1 scenarios 2 and 4, and the FR-004 guarantee that the state file survives `PIPELINE_COMPLETE`, were untested.

**Why this matters:** If `advance` started deleting the file (as the neutral doc text claims), the done banner and plan would silently disappear.

**How it was resolved:** New tests: advance plan to tasks (banner `5/8`, four stages completed), and the final advance from review-code (prints `PIPELINE_COMPLETE`, state file kept, done banner, all eight completed).

### FINDING-8
- **Severity:** Important
- **Confidence:** 90
- **File:** tests/test_ship_state.sh (banner injection block)
- **Category:** test-quality
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The first injection tests used payloads with spaces. The status line splits fields on IFS, so those payloads were cut off and would pass even without the guard.

**Why this matters:** The FINDING-5 fix had no effective regression test.

**How it was resolved:** The payloads now contain no whitespace (`a[$(id>FILE)]`). Against the pre-fix script the tests fail (the command runs); against the fixed script they pass.

### FINDING-9
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-ship-statusline.sh (banner validation)
- **Category:** external
- **Source:** codex
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** Digit-only strings with a leading zero (`"08"`, `"00"`) passed the check, but bash reads them as octal, which gives an arithmetic error or a division by zero.

**Why this matters:** For malformed states, the banner fails with an error instead of being skipped cleanly.

**How it was resolved:** Leading zeros are rejected (a total of zero too). Test added.

**External tool analysis (Codex):**
> If a state file contains string values such as `total_stages: "00"` or `stage_index: "08"`, these digit-only checks accept them, but Bash arithmetic interprets leading-zero values as octal.

### FINDING-10
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-ship-statusline.sh (banner validation)
- **Category:** external
- **Source:** codex
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** A very large `stage_index` with a small total made the progress-bar loop draw an enormous bar.

**Why this matters:** The banner caller could stall until the 5 second timeout.

**How it was resolved:** At most two digits, and the index must not exceed the total. Test added.

### FINDING-11 to FINDING-20 (Minor, fixed)
- **FINDING-11** (security, round 1): control codes and printf directives in `stage` reached the verbatim banner. Fixed by the stage allowlist in banner mode.
- **FINDING-12** (correctness, round 1): a multi-line array with its items on the opening line and `]` on its own line was refused with a misleading parse error. Now handled, and a failed verification raises "did not verify".
- **FINDING-13** (correctness/architecture, round 1): the neutral ship text says `advance` removes the state file, while the Codex and OpenCode tokens say the opposite. The neutral sentence cannot change (FR-016), so the token text now states that it overrides that sentence and that only `cleanup` removes the file.
- **FINDING-14** (architecture, round 1): when the prompt hook resumes a paused pipeline, the agent might skip `resume` and therefore `progress`. The tokens now say to run `progress` after any reply to a pause.
- **FINDING-15** (architecture, round 1): SKILL.md read `--integration auto` too narrowly. It now counts `auto` when it resolved to Codex.
- **FINDING-16** (production, round 1): SKILL.md had no path for a non-zero or unexpected `check` result. Now: do not ask, report the error and the hint.
- **FINDING-17** (test-quality, round 1): there were no tests for the `~/.codex` fallback without `CODEX_HOME`, or that `check` writes nothing. Both added.
- **FINDING-18** (test-quality, round 1): no test for FR-019. Added a negative check that Claude init, `setup.yml` and `spex-init.sh` never reference the Codex progress setup.
- **FINDING-19** (correctness, round 2): with dotted or inline `tui` keys, the snippet told the user to edit an "existing [tui] table". It now chooses its form from the file text.
- **FINDING-20** (correctness, round 2): `harness` and `security` had the same unhashable TypeError as FINDING-4. Guarded and tested.

## Remaining Findings

### FINDING-21
- **Severity:** Minor
- **File:** spex/codex/skills/cc-spex-init/scripts/codex-progress.sh:13-16
- **Category:** security
- **Source:** security-agent
- **Resolution:** remaining (design decision)

`apply` is the one subcommand that runs with sandbox escalation. Like `bootstrap.sh`, the wrapper resolves the Python tool from `SPEX_SOURCE` or a `./spex` tree in the current directory before the bundled plugin tree, so a repository that plants a `spex/` tree could get its own script run unsandboxed. The approval prompt only shows the wrapper path. Possible fix: for `apply`, resolve only from the bundled plugin tree. This was left as is to keep the resolution policy consistent with `bootstrap.sh` and the dev workflow inside the cc-spex repository.

### FINDING-22
- **Severity:** Minor
- **File:** spex/scripts/spex-ship-state.py:354-370
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining (design decision)

The "is this a ship state" test and the current position are decided twice: in Python for the plan (from `stage_index`) and in bash for the banner (from `stage`). They agree for every state the scripts write, but differ for hand-made inconsistent files. Possible fix: print PLAN only when the banner rendered, or derive the plan from `stage`.

### FINDING-23
- **Severity:** Minor
- **File:** spex/codex/skills/cc-spex-init/scripts/codex-progress.sh:13-28
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining

The three-step source resolution is copied from `bootstrap.sh`, and the copy is already looser (it does not check that `SPEX_SOURCE` holds a complete Spex source). Possible fix: a shared `resolve-source.sh` sourced by both scripts.

### FINDING-24
- **Severity:** Minor
- **File:** spex/codex/skills/cc-spex-init/SKILL.md:93-94
- **Category:** architecture
- **Source:** architecture-agent
- **Resolution:** remaining (partially fixed)

SKILL.md has the agent work out the config path itself (`$CODEX_HOME` or `~/.codex`), duplicating `config_path()`. The duplicate `snippet` call was removed (the agent now reuses the output of `apply`). Possible fix: have `check` print `ASK path=<path>`.

## Notable Observations

### NOTABLE-1
- **File:** spex/scripts/adapters/opencode/command-map.json:6
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The OpenCode token repeats most of the Codex token, and the adapter cannot share text across command maps.
- **Rationale:** The two JSON strings will drift. A `progress --banner-only` flag or shared fragments would help.

### NOTABLE-2
- **File:** spex/scripts/spex-setup-profile.py:37
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** `codex_progress: "declined"` is a personal choice about a user's global Codex config, stored in the team-owned `.specify/spex.json` (as FR-024 requires). Once committed, one teammate's "no" stops the question for everyone.
- **Rationale:** Worth documenting, or moving later to an untracked per-user file.

### NOTABLE-3
- **File:** Makefile
- **Category:** test-quality
- **Source:** test-quality-agent
- **Description:** There is no aggregate `test` target, `release` and CI do not run the feature's tests, and `make help` lists none of the per-area targets.
- **Rationale:** The Claude non-regression guards only run when someone runs them by hand.

### NOTABLE-4
- **File:** spex/scripts/spex-ship-statusline.sh:311,330
- **Category:** security
- **Source:** re-review agent
- **Description:** The Claude (non-banner) status line still evaluates `stage_index` and `total_stages` in bash arithmetic, which can run `a[$(cmd)]` from a tampered state file. This predates the feature. It was left unchanged here because FR-012 requires byte-identical Claude output; a digits-only check would only change output for hostile files.
- **Rationale:** A small follow-up hardening for the Claude path.

## Post-Fix Spec Coverage

The fix loop replaced lines but removed no functions, files or behavior. All spec requirements were verified after the fix loop: adapter output for Claude (byte-identical to main), Codex and OpenCode; banner and plan for running, paused, failed, `--start-from`, advance and done states; config edits for every FR-027 case. Coverage: 29/29 functional requirements.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | per-area targets (no aggregate `make test`): test_adapt_ship_progress, test_ship_state, test_resume_paused, test_ship_statusline, test_cc_spex_codex_plugin, test_generated_trees, test_codex_progress, test_setup_profile | 0 | 0 | passed |
| 2 | same, plus test_apply_extensions, test_workflow_setup, sync-scripts-check | 0 | 0 | passed |
| 3 | test_ship_state, test_ship_statusline, test_resume_paused, sync-scripts-check | 0 | 0 | passed |

The test suite passed in all fix rounds. The new regression tests were checked against the pre-fix scripts and fail there as expected.
