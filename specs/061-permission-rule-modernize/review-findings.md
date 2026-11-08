# Deep Review Findings

**Date:** 2026-11-03
**Branch:** 061-permission-rule-modernize
**Rounds:** 3
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 9 | 9 | 0 |
| Minor | 15 | 12 | 3 |
| Notable | 3 | - | 3 |
| **Total** | **28** | **22** | **6** |

**Agents completed:** 5/6 (Goal Alignment skipped: no PR found) + 2 external tools (CodeRabbit, Codex); Copilot disabled in config. Two internal re-review agents ran on the fix diffs (rounds 1 and 2).
**Agents failed:** none

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-permissions.sh (migrate_file, do_apply, safe_write)
- **Category:** security
- **Source:** security-agent (also reported by: coderabbit x2, codex)
- **Round found:** 1
- **Resolution:** fixed (round 1, hardened in rounds 2 and 3)

**What is wrong:** migrate and apply never checked whether the project settings path leads to the user-level settings. A symlinked `.claude/settings.json`, a symlinked `.claude` directory, or running from `$HOME` let spex rewrite `~/.claude/settings.json`; YOLO apply wrote `bypassPermissions` and bare `Bash`/`Edit`/`Write` into the global file.

**Why this matters:** FR-012 forbids reading or modifying user-level settings. A cloned repository could ship such a symlink and widen the user's permissions in every project.

**How it was resolved:** `project_target` canonicalizes each project settings path once (`canon`, `phys_dir` with `cd -P`) and refuses it with `WARNING: <file> resolves to the user-level Claude settings; left unchanged` when it names `settings.json` or `settings.local.json` in `~/.claude` or `$CLAUDE_CONFIG_DIR`. All reads and writes use that canonical path, and `safe_write` re-checks before writing. Tests cover file links, directory links, home as root (with and without `~/.claude`), and `CLAUDE_CONFIG_DIR`.

**External tool analysis (CodeRabbit):**
> Update migrate_file so it resolves the target and skips user-level settings before reading or writing them; ensure both migrate and apply honor this boundary.

**External tool analysis (Codex):**
> If `.claude/settings.json` points to `$HOME/.claude/settings.json`, this write follows the symlink and modifies user-wide permissions. Exclude resolved user-settings targets before reading or writing, including targets reached through directory symlinks.

### FINDING-2
- **Severity:** Critical
- **Confidence:** 92
- **File:** spex/scripts/spex-permissions.sh (is_user_settings)
- **Category:** security
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The round 1 guard compared the fully resolved project path with the unresolved user path. When `~/.claude/settings.json` is itself a symlink (GNU stow, home-manager, chezmoi), every bypass from FINDING-1 still worked.

**Why this matters:** Same impact as FINDING-1, for a common dotfile layout.

**How it was resolved:** Both sides are canonicalized with `canon`. New tests use dotfile-style symlinked user settings; they fail on the round 1 code (15 failures) and pass now.

### FINDING-3
- **Severity:** Important
- **Confidence:** 95
- **File:** spex/scripts/spex-permissions.sh (is_user_settings)
- **Category:** security
- **Source:** re-review agent (round 2)
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** Path identity was decided by string comparison. On case-insensitive APFS, `SETTINGS.JSON` or `.CLAUDE` links named the same file under a different string. Hard links were invisible too.

**Why this matters:** FR-012 bypass on the platform this repository is developed on.

**How it was resolved:** `same_file` compares existing files with `-ef` (device and inode) and not-yet-existing files by directory identity plus a case-insensitive name. Tests for hard links and case variants (skipped on case-sensitive file systems).

### FINDING-4
- **Severity:** Important
- **Confidence:** 92
- **File:** spex/scripts/spex-permissions.sh (canon, migrate_file, do_apply)
- **Category:** security
- **Source:** re-review agent (round 2) (also reported by: codex, round 3 diff)
- **Round found:** 3
- **Resolution:** fixed (round 3)

**What is wrong:** The checked path and the read path differed: `readlink` output in a command substitution loses trailing newlines, so a link named `foo\n` sent the check to `foo` while jq read the user settings through the kernel and copied them (including `env` secrets) into a new project file. A canonical path ending in a newline was also truncated by the caller.

**Why this matters:** User settings and their secrets could land in the repository tree.

**How it was resolved:** `canon` keeps link-target newlines, fails when its result is not the file the kernel opens (`-ef`), and fails for results that end in a newline; `project_target` then warns `cannot be resolved safely; left unchanged`. Every read uses the canonical path. Regression tests for both cases.

### FINDING-5
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-permissions.sh (phys_dir)
- **Category:** external
- **Source:** coderabbit (round 1 diff) (also reported by: re-review agent round 1, as Minor)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** `phys_dir` used a logical `cd`, so `..` after a symlinked directory was collapsed textually while the kernel resolves it physically; `..` after a missing directory was not handled.

**Why this matters:** The checked path could differ from the written path.

**How it was resolved:** `cd -P`, and `.`/`..` after a missing directory fail (fail closed). Test with a relative `..` link behind a symlinked `.claude`.

**External tool analysis (CodeRabbit):**
> Update phys_dir to resolve directory paths physically, including paths containing symlinks followed by .., before the user-settings comparison.

### FINDING-6
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/scripts/spex-permissions.sh (do_apply rule array)
- **Category:** external
- **Source:** codex (round 1 diff)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** The jq 1.5 compatible rule serialization (`printf '%s\n' "$@" | jq -R`) split a rule containing a newline into several rules, for example smuggling a bare `Bash`.

**Why this matters:** Permission widening through a malformed argument.

**How it was resolved:** One `jq --arg` call per rule keeps argument boundaries and still works with jq 1.5. Test added.

**External tool analysis (Codex):**
> If a single rule argument contains a newline, `jq -R` splits it into separate permissions rather than preserving it verbatim ... unintentionally granting unrestricted Bash access.

### FINDING-7
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/scripts/spex-init.sh (do_refresh, do_update)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** No test exercised the `--refresh` or `--update` entry points (US2, FR-004), so a broken script path or a dropped `migrate_permissions` call would pass the suite.

**How it was resolved:** tests/test_init_worktrees_git.sh now covers refresh (both files, other keys kept, second run byte-identical with no `Migrated:` line), refresh with invalid JSON (warning, refresh completes), and update (with a `uv` stub).

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** tests/test_permissions.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The test YOLO list was a hand copy of setup.yml only; nothing read the rule lists in spex/skills/init/SKILL.md or setup.yml, so a reintroduced `Read(*)` would not fail any test (FR-001, FR-014, FR-016).

**How it was resolved:** Static checks extract the Standard, YOLO and None bash blocks from SKILL.md and the apply calls from setup.yml and reject legacy forms; the SKILL.md YOLO block is executed against a fixture with legacy rules in both files. The misleading comment was corrected.

### FINDING-9
- **Severity:** Important
- **Confidence:** 85
- **File:** tests/test_permissions.sh
- **Category:** test-quality
- **Source:** re-review agent (round 1)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** All FR-012 tests used regular files for the fake user settings, which is why FINDING-2 passed the suite.

**How it was resolved:** Dotfile-style symlinked user settings and a relative `..` link case were added.

### FINDING-10 to FINDING-21 (Minor, fixed)
- setup.yml printed `Claude Code permissions configured ($LEVEL)` unconditionally, contradicting `WARNING: ... permissions not applied` (architecture, production, correctness agents). Now it only names the level before `apply`; the script reports the result.
- Usage text duplicated in `usage` and `--help` (architecture). Shared `usage_text`.
- No trap for the temporary file on interruption (production). EXIT/INT/HUP/TERM traps around the temp file lifetime.
- `cat > "$_tmp" 2>/dev/null` leaked a raw shell error for read-only targets (production, correctness). Redirections are grouped in braces; test asserts the warning is the only output.
- `$ARGS.positional` required jq 1.6 (production). Replaced, see FINDING-6.
- Missing jq made `migrate` print `ERROR:` and exit 1 even without settings files, which makes the init skill stop (correctness). migrate now exits 0, silent without files and with a `WARNING:` per existing file; apply keeps exit 1.
- `Migrated:` assertions for the spex-detach migration could no longer tell the two migrations apart (test quality). They match `Migrated: removed spex-detach`.
- Non-Claude harness edge case untested (test quality). Codex workflow case added.
- A defaultMode-only change gave no restart advice (CodeRabbit, two comments). apply prints `Default mode set to <mode> in <file>`; the init skill treats it as a restart reason.
- Home-as-root apply test lacked exit code and warning assertions (re-review round 1). Added.
- Hard links to user settings were not detected (re-review round 2). Fixed with `-ef`, see FINDING-3.
- `CDPATH` or a leading `-` could redirect `cd` in `phys_dir` (re-review round 2). `unset CDPATH` and a `./` prefix; test added.

## Remaining Findings

### FINDING-22 (Minor, remaining)
- **File:** spex/scripts/spex-permissions.sh:do_apply with spex/skills/init/SKILL.md Step 2
- **Category:** architecture
- **Source:** architecture-agent

`apply` migrates only `.claude/settings.json`, so the skill runs `apply` and then `migrate`. With an invalid `settings.json` the user sees two warnings for the same file. Folding `settings.local.json` migration into `apply` would remove the duplicate and the call protocol. Left as is: it changes the apply contract and the skill text, and the output is still correct. Judgment call (API design).

### FINDING-23 (Minor, remaining)
- **File:** tests/test_workflow_setup.sh
- **Category:** test-quality
- **Source:** test-quality-agent

No workflow-level case with an invalid settings file checks that the setup report relays the `WARNING:` lines (FR-010). Covered at script level and for refresh in tests/test_init_worktrees_git.sh. Clear-cut, low risk.

### FINDING-24 (Minor, remaining)
- **File:** spex/scripts/spex-permissions.sh:migrate_file
- **Category:** external
- **Source:** codex (round 3 working tree)

A dangling settings symlink or a symlink loop is skipped silently by `migrate` (the `-f` test fails before `project_target`). This matches FR-011 (a missing file is left alone without output); the contract table was clarified instead of adding a warning. Judgment call (requirement interpretation).

## Notable Observations

### NOTABLE-1
- **File:** spex/skills/init/SKILL.md:74-91, spex/setup.yml (claude-permissions)
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The per-level rule lists live in two places and already differ (the skill's YOLO list has the `Bash(specify *)` family, setup.yml has `Agent(*)` and the plan/worktree tools). This predates the feature.
- **Rationale:** A follow-up `spex-permissions.sh apply --level standard|yolo` with the lists defined once would make interactive init and workflow setup consistent.

### NOTABLE-2
- **File:** spex/scripts/spex-permissions.sh (migrate_file, do_apply)
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** Read-modify-write without a lock or change check; Claude Code itself writes `settings.local.json`.
- **Rationale:** The window is milliseconds today; relevant if migrations ever run from hooks or in parallel.

### NOTABLE-3
- **File:** spex/scripts/spex-permissions.sh (project_target, safe_write)
- **Category:** security
- **Source:** re-review agent (round 2)
- **Description:** Check-then-act between resolution and write. `safe_write` re-resolves and re-checks the target, which closes the redirect to user settings, but a concurrent writer in `.claude/` could still swap files.
- **Rationale:** Needs a concurrent attacker with write access to the project, who could already do worse.

## Post-Fix Spec Coverage

The fix loop removed code (the inline setup.yml summary line, `resolve_link`, the `$ARGS.positional` serialization). Every requirement was re-checked:

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001, FR-014 interactive YOLO bare rules, skill explanation | SKILL.md YOLO block; executed by tests/test_permissions.sh | ✓ |
| FR-002 workflow YOLO bare rules | setup.yml claude-permissions; tests/test_workflow_setup.sh | ✓ |
| FR-003, FR-017 merge collapses legacy, keeps order | JQ_APPLY + mig | ✓ |
| FR-004 every entry point migrates | setup.yml migrate-permissions, spex-init.sh migrate_permissions, SKILL.md blocks | ✓ |
| FR-005, FR-006 exact strings, dedup of bare names only | JQ_DEFS mig | ✓ |
| FR-007, FR-008, FR-009a other keys kept, no-op keeps bytes | JQ_MIGRATE status unchanged, safe_write only on change | ✓ |
| FR-009, FR-010 Migrated line format, visible everywhere | migrate_file/do_apply output; spex-setup-report.sh; SKILL.md Step 4 | ✓ |
| FR-011, FR-011a broken/partial files, write failure | is_json_document, shape guard, safe_write | ✓ |
| FR-012 never user-level settings | project_target, is_user_settings, same_file, canon | ✓ |
| FR-013, FR-015 docs | SKILL.md, README.md, spex/docs/help.md, spex/extensions/spex/docs/help.md | ✓ |
| FR-016 single script | spex/scripts/spex-permissions.sh | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

No `make test` target exists, so the relevant suites were run directly after every round.

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | tests/test_permissions.sh, tests/test_workflow_setup.sh | 0 | 0 | passed (181 checks; 15 workflow cases) |
| 1 | test_permissions.sh, test_init_worktrees_git.sh, test_workflow_setup.sh, test_cc_spex_codex_plugin.sh, test_apply_extensions.sh, make sync-scripts-check | 0 | 0 | passed (240; 70; 16 cases; 94; 83) |
| 2 | test_permissions.sh (sh and dash), test_init_worktrees_git.sh, test_workflow_setup.sh | 0 | 0 | passed (274; 70; 16 cases) |
| 3 | test_permissions.sh (sh and dash), test_init_worktrees_git.sh, test_workflow_setup.sh, test_cc_spex_codex_plugin.sh, test_apply_extensions.sh, make sync-scripts-check | 0 | 0 | passed (300; 70; 16 cases; 94; 83) |

New regression tests were confirmed to fail on the code of the previous round (round 1 code: 15 failures; round 2 code: 11 failures).

Test suite passed in all fix rounds.
