# Implementation Plan: Detach Stealth-Mode Exclude Gap and Config Loss on Refresh

**Branch**: `060-detach-exclude-fix` | **Date**: 2026-11-03 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/060-detach-exclude-fix/spec.md`

## Summary

Selecting spex-detach in setup enables the extension but never writes its exclude entries, and every refresh resets the detach configuration to the template. The fix adds two detach subcommands (`verify`, `ensure`) and calls `ensure` from `spex-apply-extensions.sh`, the one script every selection path goes through, so entries are written, verified, and repaired on refresh. A new `spex-detach-config.sh save|restore` script keeps the configuration across reinstall in both installers (`setup.yml` and `spex-init.sh`), saving before anything is uninstalled. See [research.md](research.md) and [contracts/cli.md](contracts/cli.md).

## Technical Context

**Language/Version**: POSIX sh (`spex-apply-extensions.sh`, new `spex-detach-config.sh`), Bash (`spex-init.sh`, tests), Python 3 stdlib (`spex-detach.py`), YAML workflow (`spex/setup.yml`)
**Primary Dependencies**: `git` (`check-ignore`, `ls-files`, `rev-parse --git-common-dir`), `jq`, `yq` (config read, existing fallback when missing), `specify` CLI
**Storage**: Files only (see [data-model.md](data-model.md))
**Testing**: Bash test scripts under `tests/` (stub `specify` for apply-extensions; real `specify` for the workflow test); new Makefile target `test-detach`
**Target Platform**: macOS and Linux developer machines
**Project Type**: Claude Code / Codex plugin (scripts + skill markdown)
**Performance Goals**: N/A (a handful of git calls per setup)
**Constraints**: No changes to `.specify/` upstream files; verification must never create files in the working tree; non-detach projects unchanged (FR-012)
**Scale/Scope**: 3 scripts changed, 1 new script, 1 workflow file, 5 test files (1 new: `test_init_detach.sh`, plus `test_detach_config_preserve.sh`), Makefile, 2 docs

## Constitution Check

| Principle | Status | Note |
|-----------|--------|------|
| I. Spec-Guided Development | Pass | Spec 060 with clarifications and review-spec decisions |
| II. Extension Architecture | Pass | New behavior lives in the spex-detach extension's script (`verify`, `ensure`); core scripts only call it |
| III. Extension Composability | Pass | apply-extensions calls detach only when detach is enabled; no other extension's files touched |
| IV. Quality Gates | Pass | Gates run in the ship pipeline |
| V. Naming Discipline | Pass | Branch `060-detach-exclude-fix`; script names follow `spex-*` |
| VI. Skill Autonomy | Pass | No skill logic changes beyond a one-line note in the init skill's report step |
| VII. State as Scripts | Pass | All logic in scripts (`spex-detach.py`, `spex-detach-config.sh`), skills only call them |

Post-design re-check: Pass, no violations, no Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/060-detach-exclude-fix/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/cli.md
└── tasks.md            # /speckit-tasks
```

### Source Code (repository root)

```text
spex/
├── extensions/spex-detach/scripts/
│   └── spex-detach.py          # + verify, + ensure [--was-enabled]
├── scripts/
│   ├── spex-apply-extensions.sh # + ensure call after the selection loop
│   ├── spex-detach-config.sh    # NEW: save | restore
│   └── spex-init.sh             # save/restore around reinstall; run_detach_enable -> ensure
├── setup.yml                    # + save-detach-config step; restore in install-ext-spex-detach
├── skills/init/SKILL.md         # report stealth lines in Step 4 alongside Enabled/Disabled
└── docs/help.md                 # doc update
README.md                        # doc update
Makefile                         # + test-detach
tests/
├── test_spex_detach.sh          # + verify/ensure cases
├── test_apply_extensions.sh     # + detach ensure cases
├── test_detach_config_preserve.sh # NEW
├── test_init_detach.sh          # NEW: spex-init.sh --refresh path (stub specify)
└── test_workflow_setup.sh       # + end-to-end detach case
```

**Structure Decision**: Existing layout; detach logic stays in the extension's own script, the config helper is a canonical script in `spex/scripts/` (called by both installers via their source path, not synced into an extension).

## Design Notes

1. **verify** (FR-002, FR-003, FR-004, FR-006): classification and probes per [data-model.md](data-model.md); re-include probes for `.specify/spex.json` and `.specify/memory/constitution.md`; `tracked` check via `git ls-files`. Never writes.
2. **ensure** (FR-001, FR-005, FR-010, FR-011): `enable` (already idempotent) then `verify`; written vs. repaired message from `paths_added` and `--was-enabled`. Outside a git repository it is silent and exits 2 (no `ERROR` line, which would stop the init skill); enable's tracked warning is suppressed inside ensure because verify reports `tracked`.
3. **apply-extensions** (FR-001, FR-012): after the loop, `state "$REGISTRY" spex-detach` = true → call ensure; `--was-enabled` when the reference state (snapshot if it knows detach, else pre-loop state) was true. Exit code unaffected.
4. **spex-init.sh**: `/spex:init --refresh` and `--update` call `install_extensions` directly (only the no-flag path delegates to the workflow), so this script needs the same fixes. `run_detach_enable` switches to `ensure --was-enabled` (it only runs when detach was enabled before), is skipped when `install_extensions` used the declaration path (apply already ran), and is now also called from `do_refresh` and `do_update`. A new `save_detach_config` runs `spex-detach-config.sh save` in the main `case` before `do_refresh`, `do_update` and the legacy path (before any project change, and outside the legacy fast path's output-discarding subshell); exit 1 on failure. `install_extensions` runs `restore` right after spex-detach is re-added.
5. **setup.yml**: `save-detach-config` step right after `validate-source`, before `snapshot-registry` (the first step that may change the project; FR-009 requires stopping before anything is changed); `install-ext-spex-detach` runs `restore` after `add`.
6. **Init skill**: Step 4 already reports `Enabled:`/`Disabled:` lines from the apply block; extend it, and the Step 1 refresh bullet, to relay `Stealth mode:`, `Repaired stealth mode:` and `WARNING: stealth mode` lines.

## Complexity Tracking

None.
