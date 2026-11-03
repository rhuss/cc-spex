# Tasks: Detach Stealth-Mode Exclude Gap and Config Loss on Refresh

**Input**: `specs/060-detach-exclude-fix/` (spec.md, plan.md, research.md, data-model.md, contracts/cli.md, quickstart.md)
**Tests**: Requested by FR-013. Write each test before or together with the code it covers.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Add a `test-detach` target to `Makefile` (and to `.PHONY` and the `help` target's list) that runs `tests/test_spex_detach.sh`, `tests/test_detach_config_preserve.sh` and `tests/test_init_detach.sh`; create `tests/test_detach_config_preserve.sh` and `tests/test_init_detach.sh` as executable skeletons reusing the assert helpers style of `tests/test_spex_detach.sh` (PASS/FAIL counters, temp repo, cleanup trap, non-zero exit on any FAIL)

## Phase 2: Foundational (blocks US1 and US3)

- [X] T002 Add `verify` subcommand to `spex/extensions/spex-detach/scripts/spex-detach.py` per contracts/cli.md: read entries with `read_exclude_paths()`, skip blank/comment/`!` entries, classify directory/glob/file (data-model.md), build probes (strip leading `/` and `**/`; glob: `**`/`*` → `spex-probe`, `?` → `x`, `[...]` → first char), check each probe with `git check-ignore -q -- <probe>`, mark `tracked` when `git ls-files -- <entry path>` is non-empty, also probe `.specify/spex.json` and `.specify/memory/constitution.md` when an entry covers them (prefix match for directories, `fnmatch` for globs); print JSON to stdout and the `Stealth mode: active (verified: ...)` or `WARNING: stealth mode is NOT fully active...` lines to stderr; exit 0/1/2; never create files; register in `COMMANDS` and the usage text. **Interfaces**: `run_verify() -> (dict, int)` returns the contract JSON dict and the exit code without printing; `cmd_verify(args)` prints and exits with it
- [X] T003 Add `ensure [--was-enabled]` subcommand to `spex/extensions/spex-detach/scripts/spex-detach.py`: call the enable logic (refactor `cmd_enable` into a function returning its result dict so `ensure` can reuse it without printing twice), print `Repaired stealth mode: added <paths>` (with `--was-enabled`) or `Stealth mode: exclude entries written: <paths>` to stderr when `paths_added` is non-empty, then run verify; stdout JSON `{"enable": ..., "verify": ...}`; exit with verify's code; keep `enable`'s existing stdout JSON and tracked warning unchanged for the `enable` subcommand, but inside `ensure` suppress enable's tracked warning (verify's `tracked` lines report it, so it is not printed twice); when `git rev-parse --git-common-dir` fails, `ensure` prints nothing, writes nothing and exits 2 (no `ERROR` line: the init skill stops on any `ERROR` in the output, and the spec requires non-git projects to be skipped without failing). **Interfaces**: `run_enable(args, warn_tracked=True) -> dict` (extracted from `cmd_enable`, raises/returns a not-a-repo marker instead of exiting), `run_verify()` from T002; `cmd_ensure(args)` accepts only `--was-enabled`
- [X] T004 [P] Add tests to `tests/test_spex_detach.sh`: verify with defaults all ignored (exit 0, active line), directory entry visible when not excluded (exit 1, warning names entry), tracked file under `specs/` reported `tracked`, file entry (`CLAUDE.md`) and glob entry (`*.local.md`) probes, `!` entry skipped, `.specify/spex.json` and constitution reported ignored with `.specify/` excluded even when spex's `!**/.specify/spex.json` re-include block is present in the exclude file, verify creates no files (`git status --porcelain` unchanged); ensure without flag prints "written", with `--was-enabled` after deleting one entry prints "Repaired ... specs/", second ensure adds nothing and each entry appears exactly once; ensure with a tracked file under `specs/` prints the tracked hint once (not twice); ensure outside a git repository exits 2 with empty stderr; a config with invalid YAML makes `verify` and `ensure` use the default path list (the written and verified lists agree)

## Phase 3: User Story 1 - Selecting detach at setup really hides spec artifacts (P1) 🎯 MVP

**Goal**: Every selection path that ends with spex-detach enabled writes and verifies the entries.
**Independent test**: `make test-apply-extensions` detach cases; quickstart manual section 1.

- [X] T005 [US1] In `spex/scripts/spex-apply-extensions.sh`, after the selection loop and the spex-worktrees git block, before the summary line: when `state "$REGISTRY" spex-detach` is `true` and `.specify/extensions/spex-detach/scripts/spex-detach.sh` is executable, run it with `ensure` (add `--was-enabled` when the detach reference state, computed like the loop's `reference` from `$BEFORE` or the pre-loop registry state, was `true`), send its stderr to stderr, discard stdout, never change `rc`; capture the pre-loop detach state before the loop runs; update the header comment to mention the stealth-mode step
- [X] T006 [US1] Add tests to `tests/test_apply_extensions.sh` (copy the real `spex/extensions/spex-detach/scripts/` into the test project's `.specify/extensions/spex-detach/scripts/` and `git init` the project): selecting spex-detach from disabled prints `Enabled: spex-detach`, `Stealth mode: exclude entries written:` and `Stealth mode: active`, and writes `.specify/`, `specs/`, `brainstorm/` to `.git/info/exclude`; a configured path that stays visible (tracked file under `specs/`) prints the WARNING and the script still exits 0; selecting spex-detach in a project that is not a git repository exits 0 and prints no `ERROR` and no stealth line
- [X] T007 [US1] In `spex/scripts/spex-init.sh`: change `run_detach_enable` to call `"$detach_script" ensure --was-enabled` and let its stderr through (keep the early returns for missing script / disabled registry); skip it when `install_extensions` applied a declaration through `spex-apply-extensions.sh` in this run (set a global flag `SPEX_DETACH_ENSURED=1` in `install_extensions`'s declaration branch and check it in `run_detach_enable`). The legacy fast path runs `(install_extensions)` in a subshell, so the flag does not reach the parent there and `ensure` runs a second time; that is harmless (idempotent, adds nothing, no repair line), keep it. Drop the `2>/dev/null` on that fast path's `run_detach_enable` call so stealth lines and warnings reach the user (FR-003/FR-004). Add a `run_detach_enable` call after `install_extensions` in `do_refresh` and `do_update`, which today never call it, so a refresh without a declaration also repairs missing entries (FR-010)
- [X] T008 [US1] In `spex/skills/init/SKILL.md` Step 4 (the report of the apply block), add that `Stealth mode: ...`, `Repaired stealth mode: ...` and `WARNING: stealth mode is NOT fully active` lines from the block's output are shown to the user verbatim, and that a stealth warning never stops init; extend the Step 1 `--refresh`/`--update` bullet (which lists the `Enabled:`, `Disabled:`, `Migrated:` lines to report) with the same three line types, since refresh output reaches Step 4 through Step 1

## Phase 4: User Story 2 - Refresh keeps the user's detach configuration (P2)

**Goal**: Detach config byte-identical across reinstall in both installers; save before anything is uninstalled.
**Independent test**: `tests/test_detach_config_preserve.sh`; workflow refresh hash compare.

- [X] T009 [P] [US2] Create `spex/scripts/spex-detach-config.sh` (POSIX sh, executable, `set -u`) with `save` and `restore` per contracts/cli.md (config `.specify/extensions/spex-detach/spex-detach-config.yml`, saved copy `.specify/.spex-detach-config.saved.yml`, `cp -p` for save, `mv` for restore, stale saved copy kept when config is missing, error messages naming the files, exit 0/1, usage exit 2)
- [X] T010 [US2] Fill `tests/test_detach_config_preserve.sh`: save+restore over a template is byte-identical (shasum) for a config with comments, custom `archive.path`, `auto_commit: false` and a custom path list; no config → both no-ops and template stays; stale saved copy with config missing → save keeps it, restore puts it back; save failure (make `.specify` read-only, skip when running as root) exits 1, prints the ERROR, leaves the config untouched; restore removes the saved copy
- [X] T011 [US2] In `spex/setup.yml`: add a shell step `save-detach-config` immediately after `validate-source` and before `snapshot-registry` (the first step that can change the project: `snapshot-registry` may rewrite `.specify/spex.json`, and `migrate-commands`/`init-project` change files too, so FR-009's "stop before anything is changed" requires the save to come first) that runs `sh "$SOURCE/scripts/spex-detach-config.sh" save` with `SOURCE="{{ steps.validate-source.output.stdout }}"` and fails the workflow on non-zero; in `install-ext-spex-detach` run `sh "$SOURCE/scripts/spex-detach-config.sh" restore || exit 1` right after `specify extension add` and before `specify extension disable`; no change to `scripts/spex-setup-report.sh` (it already prints a failed step's stderr)
- [X] T012 [US2] In `spex/scripts/spex-init.sh`: add `save_detach_config()` (runs `sh "<plugin_root>/scripts/spex-detach-config.sh" save`, on failure lets the ERROR through and `exit 1`) and call it in the main `case` before `do_refresh`, before `do_update`, and on the legacy path before `migrate_phase_marker` (so it runs before `specify init --force`, `migrate_old_commands` and the `(install_extensions)` subshell, whose output and exit status would otherwise hide the failure); not on the workflow-delegation path (setup.yml saves itself) or `--clear`. In `install_extensions`, right after `specify extension add` succeeds for `spex-detach`, run `restore` and `exit 1` (after removing any snapshot temp file) on failure

## Phase 5: User Story 3 - Refresh repairs projects set up before the fix (P3)

**Goal**: Missing entries restored on refresh with a repair message; idempotent.
**Independent test**: apply-extensions repair cases; workflow double refresh.

- [X] T018 [US2] [US3] Fill `tests/test_init_detach.sh` for the Claude refresh path (`spex-init.sh --refresh`, which calls `install_extensions` directly, not the workflow), reusing the stub-`specify` pattern of `tests/test_init_worktrees_git.sh` but with `extension remove` deleting `.specify/extensions/<id>/` and `extension add` copying the source extension directory (template config included): with a declaration naming spex-detach and a customized config → config shasum identical, entries missing from `.git/info/exclude` → output contains `Repaired stealth mode`; with a declaration not naming spex-detach (installed, disabled) → config identical, no stealth output; without a declaration and spex-detach enabled → missing entries repaired (via `do_refresh`'s `run_detach_enable`); save failure (read-only `.specify`, skipped as root) → exit 1, output names the config file, the stub call log contains no `extension remove` and no `init`
- [X] T013 [US3] Add tests to `tests/test_apply_extensions.sh`: registry and `--before` snapshot both show spex-detach enabled, exclude file lacks all entries → `Repaired stealth mode: added .specify/ specs/ brainstorm/`; only `specs/` missing → repair names only `specs/`; all present → no repair line but `Stealth mode: active`; running apply twice leaves each entry exactly once

## Phase 6: User Story 4 - Projects without detach are unaffected (P3)

- [X] T014 [US4] Add tests to `tests/test_apply_extensions.sh`: selection without spex-detach (detach installed and disabled) → no `Stealth mode` / `Repaired` output and `.git/info/exclude` byte-identical before and after; deselecting a previously enabled spex-detach (entries present) → `Disabled: spex-detach`, entries left in place, no stealth output; detach installed but scripts missing → no output, exit code unchanged

## Phase 7: Polish & Cross-Cutting

- [X] T015 Extend `tests/test_workflow_setup.sh` with an end-to-end detach case using the real workflow: setup with `-i extensions=spex-detach`; `git check-ignore` reports `specs/x/spec.md`, `.specify/spex.json`, `.specify/memory/constitution.md`, `brainstorm/x.md` ignored; customize the detach config with `yq`, refresh, compare shasum (identical); refresh again with a selection that leaves spex-detach out (installed, disabled), compare shasum again (identical, US2 scenario 3); delete `specs/` from the exclude file, refresh, check `spex-setup-report.sh` output contains `Repaired stealth mode` and the entry appears exactly once after a second refresh
- [X] T016 [P] Update `README.md` (spex-detach description / extension section) and `spex/docs/help.md` (spex-detach entry): selecting spex-detach in setup writes and verifies the exclude entries and warns on any still-visible path; refresh keeps the detach configuration and repairs missing entries; the new `spex-detach.sh verify` subcommand; config defaults changed in later releases reach only new installs
- [X] T017 [P] Update `spex/extensions/spex-detach/commands/speckit.spex-detach.detach.md` to mention `verify` as the way to check stealth mode, and run `make test-detach test-apply-extensions test-workflow-setup test-worktree sync-scripts-check` (`test-worktree` includes `tests/test_init_worktrees_git.sh`, which exercises the changed `spex-init.sh`); all must pass

## Dependencies

- T001 → T004, T010
- T002 → T003 → T004, T005, T007
- T005 → T006, T013, T014; T007 → T008
- T009 → T010, T011, T012
- T001, T007, T012 → T018
- US1 (T005-T008) and US2 (T009-T012) are independent after Phase 2
- T015 needs T005, T011, T012; T018 needs T007, T012; T016, T017 last

## Parallel Opportunities

- T004 (tests in test_spex_detach.sh) alongside T005 once T003 is done
- T009 (new script) in parallel with all of Phase 2 and US1
- T016 and T017 in parallel at the end

## Implementation Strategy

MVP is US1 (T001-T008): it closes the leak. US2 then stops config loss, US3 is mostly covered by `ensure --was-enabled` and only needs tests, US4 is regression tests. Polish adds the end-to-end test and docs.
