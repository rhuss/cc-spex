# Implementation Plan: Ship Progress in Codex

**Branch**: `058-codex-ship-progress` | **Date**: 2026-10-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/058-codex-ship-progress/spec.md`

## Summary

Make a running ship pipeline visible in Codex without changing anything for Claude. A new `progress` subcommand of the ship state script prints a plain-text banner (rendered by the existing Claude status line script in a new color-free `--banner` mode, so icons and bar have one source) and the eight-stage plan as JSON. The harness-neutral ship command gets one empty `ship-progress` block marker; the Codex command map expands it into a short rule (run `progress` after every state command, show the banner, pass the plan to `update_plan`, no other plans until completion), OpenCode gets the banner part only, Claude gets nothing. Codex init offers once to append `task-progress` to the user's Codex footer and terminal title, using a new script that edits the TOML line by line and verifies the result with `tomllib`; a decline is stored in `.specify/spex.json`.

## Technical Context

**Language/Version**: Bash (POSIX `sh` for shims, `bash` for the status line), Python 3.11+ (`tomllib`) for state, profile and config scripts, Markdown for commands and skills

**Primary Dependencies**: `jq`, `specify` CLI, Python standard library only (no new packages)

**Storage**: Files: `.specify/.spex-state` (read), `.specify/spex.json` (new optional field), Codex `config.toml` (two `[tui]` keys)

**Testing**: Bash test scripts under `tests/` (pattern of `tests/test_ship_statusline.sh`), Python `unittest` (pattern of `tests/test_setup_profile.py`), wired into `Makefile` targets

**Target Platform**: macOS and Linux shells running Claude Code, Codex CLI (0.164+), OpenCode

**Project Type**: Plugin (Markdown commands + helper scripts)

**Performance Goals**: `progress` completes in well under a second; no new work on the Claude status line hot path

**Constraints**: Claude adapted commands and Claude status line output byte-identical (SC-003, FR-012); no edits to `.specify/` upstream files; no new dependencies; config edits atomic and limited to two lists

**Scale/Scope**: ~8 files changed, 3 new scripts/wrappers, 3 new test files, docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Spec 058 drives the work; brainstorm 51 is the input |
| II. Extension Architecture | Pass | Ship command changes stay in the `spex` extension; adapter maps in `spex/scripts/adapters/` |
| III. Extension Composability | Pass | No new cross-extension dependency |
| IV. Quality Gates | Pass | Normal ship gates apply |
| V. Naming Discipline | Pass | Scripts follow `spex-*` naming; marker key `ship-progress` follows existing kebab-case keys |
| VI. Skill Autonomy | Pass | Init skill gains one self-contained section; ship command delegates to scripts |
| VII. State as Scripts | Pass | Banner, plan, config edit and decline are all scripts; the markdown only says when to call them |
| Plugin constraints (canonical scripts, sync) | Pass | New logic in canonical `spex/scripts/`; `spex-ship-state.py` and `spex-ship-statusline.sh` already in `SCRIPTS_spex`; run `make sync-scripts` |
| No compiled artifacts / deps | Pass | Python stdlib only |

Post-design re-check: Pass (no new violations; no Complexity Tracking entries).

## Project Structure

### Documentation (this feature)

```text
specs/058-codex-ship-progress/
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
├── scripts/
│   ├── spex-ship-statusline.sh        # + --banner mode (no other change in output)
│   ├── spex-ship-state.py             # + progress subcommand
│   ├── spex-adapt-commands.sh         # empty-token support (jq -j, inline rc==0)
│   ├── spex-setup-profile.py          # + optional codex_progress, decline-codex-progress
│   ├── spex-codex-progress.py         # NEW: check/apply/snippet/decline
│   └── adapters/
│       ├── claude/command-map.json    # + "ship-progress": ""
│       ├── codex/command-map.json     # + ship-progress (banner + update_plan rule)
│       └── opencode/command-map.json  # + ship-progress (banner only)
├── extensions/spex/
│   ├── commands/speckit.spex.ship.md  # + empty {harness:ship-progress} block
│   └── scripts/                       # synced copies (make sync-scripts)
├── codex/skills/cc-spex-init/
│   ├── SKILL.md                       # + "Codex progress display" section
│   └── scripts/codex-progress.sh      # NEW: source-resolving wrapper
└── docs/help.md                       # Codex progress notes
README.md                              # Codex progress notes
CHANGELOG.md                           # entry
Makefile                               # test-adapt, test-codex-progress targets
tests/
├── test_ship_statusline.sh            # + byte-identical goldens, --banner cases
├── test_ship_state.sh                 # + progress cases
├── test_adapt_ship_progress.sh        # NEW
├── test_codex_progress.py             # NEW
└── test_setup_profile.py              # + codex_progress cases
```

**Structure Decision**: Extend the existing scripts that already own each concern (status line rendering, ship state, adapter, setup profile) and add one new canonical script for the Codex config. The init skill only orchestrates.

## Implementation Notes

1. **Goldens first**: capture the current Claude status line output (raw, with ANSI) for running/paused/failed/done/flow/watch fixtures before touching `spex-ship-statusline.sh`, and assert them in `tests/test_ship_statusline.sh`.
2. **`--banner` mode**: parse the flag before reading stdin; when set, skip stdin, chain output, `read_extensions` and `render_context`, blank all color variables, render only ship mode (including the legacy no-mode-with-stage case), print a trailing newline, never delete state files (the flow staleness check does not apply).
3. **`progress`**: never fails the pipeline: catch read/parse errors and print nothing; run the banner script with `stdin=DEVNULL`, a short timeout and `SHIP_STATE_FILE` set to the resolved absolute state path.
4. **Ship command marker**: insert the two marker lines with no surrounding blank lines of their own, directly after the last line of the "Stage Transitions" section's final paragraph, so the Claude expansion restores the original bytes.
5. **Codex token wording**: say "the `progress` command" and refer to the stage list as "the eight pipeline stages" without enumerating them; include the inline-stage-skill rule (FR-007) verbatim enough for the adapter test to find `update_plan`.
6. **Config editor**: implement as pure functions (`plan_edit(text) -> new_text`) so unit tests run on strings; file I/O and `CODEX_HOME` resolution in a thin layer.
7. **Docs**: README Codex section + help.md: what the user sees during a Codex ship run, the init question, and the manual `/statusline` + `/title` path.

## Complexity Tracking

No violations.
