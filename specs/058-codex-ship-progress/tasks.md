# Tasks: Ship Progress in Codex

**Input**: Design documents from `specs/058-codex-ship-progress/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md, quickstart.md

**Tests**: Requested by the spec (FR-027). Test tasks precede the implementation they cover.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: User story from spec.md (US1..US4)

---

## Phase 1: Setup

- [X] T001 Add Makefile targets `test-adapt` (runs `tests/test_adapt_ship_progress.sh`) and `test-codex-progress` (runs `python3 -m unittest tests/test_codex_progress.py`) and add both new targets to `.PHONY` in `Makefile`

---

## Phase 2: Foundational (blocking)

**Purpose**: Lock current Claude behavior before changing shared code, and make empty marker expansion possible.

- [X] T002 Capture golden outputs of the current `spex/scripts/spex-ship-statusline.sh` (raw bytes including ANSI, via `SHIP_STATE_FILE` fixtures, no stdin JSON and with a stdin JSON carrying `context_window.used_percentage`) for ship running (smart/always/never), paused, failed, done, legacy no-mode ship, flow, and watch states; add byte-exact assertions for them to `tests/test_ship_statusline.sh` (store expected strings inline with `$'...'` escapes). Run the test against the unchanged script and confirm it passes before any edit to the status line.
- [X] T003 Write `tests/test_adapt_ship_progress.sh`: (a) a fixture command tree in a temp dir containing a command with a `{harness:demo}`/`{/harness:demo}` block placed with no surrounding blank lines and an inline `{harness:demo-inline}` token, plus a temp adapters dir whose maps set `demo` and `demo-inline` to `""`; assert the adapted output equals the input with the marker lines/tokens removed and contains no fallback note and no extra blank line; (b) adapt the real `spex/extensions` tree for `claude` and assert the result equals the adaptation of a copy where the two `ship-progress` marker lines are deleted from `spex/commands/speckit.spex.ship.md`; (c) assert the Codex adaptation of the ship command contains `progress`, `BANNER`, `PLAN`, `update_plan`, the inline-stage-skill rule (match "do not call `update_plan`"), and no raw `{harness:ship-progress}`; (d) assert the OpenCode adaptation contains `progress` and `BANNER` but not `update_plan`. Make it executable.
- [X] T004 Change `spex/scripts/spex-adapt-commands.sh` so token files are written with `jq -j` (no trailing newline) and the inline replacement treats `getline` returning 0 (existing empty file) as an empty replacement, keeping the fallback only for a missing token file (`rc < 0`). Run `tests/test_adapt_ship_progress.sh` part (a).

**Checkpoint**: goldens pass on unchanged status line; adapter supports empty expansion.

---

## Phase 3: User Story 1 - See the current stage in a Codex ship run (Priority: P1) 🎯 MVP

**Goal**: Banner and eight-stage plan at start and after every advance and at completion.

**Independent Test**: `spex-ship-state.sh progress` against state fixtures prints the expected `BANNER`/`PLAN`; the Codex-adapted ship command carries the progress rule.

### Tests for User Story 1

- [X] T005 [P] [US1] Add `--banner` cases to `tests/test_ship_statusline.sh`: running `specify` (index 0) → `🧬 ship 📝 specify ▓░░░░░░░░ 1/8 🧠`, running `implement` (index 6) → `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`, done → `🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8`; assert no ESC byte, no bracketed extension list (`[...]`), no `%`, trailing newline present; oversight icons `always` (👁️) and `never` (🚀); unknown stage name → generic ⚙️ icon, exit 0; missing state file, invalid JSON, flow state and watch state → empty output and exit 0; `--banner` does not block when stdin is an open pipe that never closes (run it in the background fed by `sleep 5 |`, wait up to 2 s by polling, fail if still running; no dependency on `timeout`, follow `tests/test_verify_gate.sh` style).
- [X] T006 [P] [US1] Add `progress` cases to `tests/test_ship_state.sh`: fresh `create` → plan with `specify` in_progress and 7 pending, `BANNER` line present; `create --start-from implement` → six completed, `implement` in_progress, `review-code` pending; fixture with `stage: done, stage_index: 8, status: completed` → 8 completed and done banner; missing file, invalid JSON and flow-mode file → no output, exit 0; unknown stage name, out-of-range or non-numeric `stage_index` → exit 0 without traceback (plan omitted or all pending, banner may still print); `PLAN` is valid single-line JSON with exactly 8 entries whose `step` values start with the `STAGES` names in order (parse with `jq`).

### Implementation for User Story 1

- [X] T007 [US1] Add the `--banner` mode to `spex/scripts/spex-ship-statusline.sh` per contracts/cli.md: detect the flag before the stdin read and skip reading stdin; skip the chained status line, the flow staleness deletion, `read_extensions` and `render_context`; set `RESET BOLD DIM CYAN BLUE GREEN YELLOW MAGENTA RED WHITE` to empty strings; render only ship mode (including legacy no-mode-with-`stage`); print a trailing newline; exit 0 with no output otherwise. Keep all non-banner code paths byte-identical (T002 goldens must still pass).
- [X] T008 [US1] Add a `progress` subcommand to `spex/scripts/spex-ship-state.py`: read `STATE_FILE`, return silently (exit 0) on missing/unreadable/invalid JSON or `mode` not `ship` (legacy: no `mode` but `stage` present counts as ship); build the plan from `STAGES` per data-model.md (completed below index, in_progress at index with ` (paused)`/` (failed)` suffix for those statuses, pending above, all completed for `stage == "done"`); run the sibling `spex-ship-statusline.sh --banner` with `stdin=subprocess.DEVNULL`, a 5 s timeout and `SHIP_STATE_FILE` set to the absolute state path; print `BANNER <text>` only if the banner is non-empty, then `PLAN <json>` with `json.dumps(..., ensure_ascii=False, separators=(", ", ": "))` on one line. Register it in `COMMANDS` and the usage text.
- [X] T009 [US1] Insert the empty block marker into `spex/extensions/spex/commands/speckit.spex.ship.md`: two lines `{harness:ship-progress}` and `{/harness:ship-progress}` directly after the last line of the "### Stage Transitions" section (the bold line "**Do NOT manually write JSON to the state file. Always use the script.**") and before the following blank line, with nothing between them. The neutral file gets no other change, so Claude output stays unchanged.
- [X] T010 [US1] Add `"ship-progress": ""` to `spex/scripts/adapters/claude/command-map.json`.
- [X] T011 [US1] Add the `ship-progress` token to `spex/scripts/adapters/codex/command-map.json`: a value starting with `\n` that renders a `### Progress Reporting (Codex)` subsection stating: Codex has no spex status line; it introduces `"$SHIP_STATE" progress` as an additional state command (prints the banner and plan); whenever the pipeline pauses (findings, blockers, retries exhausted) run `"$SHIP_STATE" pause` first, and whenever a stage fails with an unrecoverable error run `"$SHIP_STATE" fail` first; after every state command that changes the pipeline (`create`, `advance`, `pause`, `fail`, `resume`, including the `resume` of `--resume`) run `SHIP_STATE_FILE="$SHIP_STATE_FILE" "$SHIP_STATE" progress`; put the text after `BANNER ` verbatim as its own line in the next reply; call `update_plan` with the JSON array after `PLAN ` as `plan`, unchanged; when `advance` prints `PIPELINE_COMPLETE`, the state file still exists (stage `done`), so run `progress` immediately, before the walkthrough draft and before anything removes the state file; if `progress` prints nothing, skip and continue; from pipeline start until `PIPELINE_COMPLETE` do not call `update_plan` for anything else in this thread, including inside stage skills that run inline (specify, clarify, plan, tasks); subagents may plan freely; the rule ends at `PIPELINE_COMPLETE`. Do not enumerate the eight stages.
- [X] T012 [US1] Add the `ship-progress` token to `spex/scripts/adapters/opencode/command-map.json`: same subsection titled `### Progress Reporting (OpenCode)` with the banner rule only, including the "run `pause`/`fail` first" rule and the `PIPELINE_COMPLETE` timing note from T011 (no `update_plan`, no plan rule).
- [X] T013 [US1] Run `make sync-scripts` to copy `spex-ship-statusline.sh` and `spex-ship-state.py` into `spex/extensions/spex/scripts/` (and any other extension listed in the Makefile), then run `make sync-scripts-check`, `tests/test_ship_statusline.sh`, `tests/test_ship_state.sh` and `tests/test_adapt_ship_progress.sh`.

**Checkpoint**: Codex ship command shows banner and checklist at every transition (MVP).

---

## Phase 4: User Story 4 - Claude Code behavior is unchanged (Priority: P1)

**Goal**: Prove byte-identical Claude command and status line.

**Independent Test**: T002 goldens and T003 part (b) pass.

- [X] T014 [US4] Run the quickstart step 3 regression check (adapt `spex/extensions` from `main` and from the branch for `claude`, `codex`, `opencode`) and confirm: no diff for `claude`; only `spex/commands/speckit.spex.ship.md` differs for `codex` and `opencode`. Record the result in `specs/058-codex-ship-progress/quickstart.md` under a new "Results" heading (date, outcome).
- [X] T015 [US4] Confirm `spex/scripts/spex-init.sh` and Claude-side init paths contain no call to `spex-codex-progress.py`/`codex-progress.sh` (`rg` check) and document the check in the T014 results.

---

## Phase 5: User Story 2 - See paused or failed state (Priority: P2)

**Goal**: Paused/failed/resumed states are reflected in banner and plan.

**Independent Test**: progress output for paused/failed/resumed fixtures.

- [X] T016 [P] [US2] Add cases to `tests/test_ship_state.sh`: after `pause` → banner ends with `⏸ paused` and the current step label ends with ` (paused)`; after `fail` → `✗ failed` and ` (failed)`; after `resume` → no suffix in banner or plan.
- [X] T017 [US2] Verify that the Codex and OpenCode `ship-progress` token texts (T011, T012) require `"$SHIP_STATE" pause` before any pause and `"$SHIP_STATE" fail` on an unrecoverable stage failure, followed by `progress`, because the neutral "Pausing" section only says "Update state file: `status: "paused"`" and no neutral path calls `fail`. Extend `tests/test_adapt_ship_progress.sh` part (c)/(d) to assert both adapted texts mention `pause` and `fail` in that rule. Do not change the neutral `speckit.spex.ship.md`.

---

## Phase 6: User Story 3 - Progress in the Codex footer and terminal title (Priority: P2)

**Goal**: Opt-in, once-per-project setup of `task-progress` in the Codex config.

**Independent Test**: `spex-codex-progress.py` against sample configs in a temp `CODEX_HOME`; profile keeps the decline.

### Tests for User Story 3

- [X] T018 [P] [US3] Write `tests/test_codex_progress.py` (unittest, temp `CODEX_HOME` and temp project root): missing file (and missing directory) → both keys created with defaults plus `task-progress`; file without `[tui]` → table appended at end, rest byte-identical; `[tui]` with single-line `status_line` lacking `task-progress` → appended, other lines identical; multi-line array with and without trailing comma → new item line with matching indentation; both lists already containing it → `UNCHANGED`, file untouched; only one list containing it → `check` prints `ASK`, `apply` changes only the other; comments and unrelated tables preserved (diff shows only added items/lines); unparseable file, inline `tui = {...}`, top-level `tui.status_line = [...]`, repeated `[tui]`, non-array value → exit 3, file untouched, snippet on stdout; read-only directory → exit 4 with snippet; `check` returns `DECLINED` when `.specify/spex.json` has `codex_progress: "declined"` and `CONFIGURED` when both lists contain the item; `snippet` ends with the exact hint line from contracts/cli.md, and for an unparseable file falls back to the defaults plus `task-progress`; `CODEX_HOME` respected; empty array `status_line = []` → becomes `["task-progress"]` (valid TOML); file without trailing newline; a `[tui.<sub>]` sub-table after `[tui]` (keys inserted into `[tui]`, not the sub-table); a comment after the closing `]`; CRLF line endings preserved; `[tui]` with only `terminal_title` → `status_line` added with defaults plus `task-progress`; `decline` records the decline and prints the hint, and when recording fails exits 1 and still prints the hint.
- [X] T019 [P] [US3] Extend `tests/test_setup_profile.py`: `validate` accepts `codex_progress: "declined"` and rejects other values; `resolve` keeps a stored `codex_progress`; `persist` round-trips it; `decline-codex-progress --root` adds it to an existing profile and creates a default profile with it when none exists.

### Implementation for User Story 3

- [X] T020 [US3] Extend `spex/scripts/spex-setup-profile.py`: optional field `codex_progress` (allowed value `"declined"`) accepted by `validate()` and included in its returned dict only when present; `resolve()` copies the stored value into the candidate; new subcommand `decline-codex-progress --root` that loads the stored profile (or `DEFAULT`), sets the field, writes with `write_atomic`, and emits the result.
- [X] T021 [US3] Create `spex/scripts/spex-codex-progress.py` per contracts/cli.md and research.md R6: config path from `CODEX_HOME` or `~/.codex/config.toml`; constants for Codex defaults (comment naming `codex-rs/tui/src/chatwidget.rs` and `status_surfaces.rs`); pure function `plan_edit(text) -> (new_text, changed)` raising an `Unsupported` error for unparseable/unsupported forms; line-based edit inside the single `[tui]` region; post-edit `tomllib` re-parse asserting only the two lists changed and equal the expected values; atomic write (temp file + `os.replace`, `mkdir -p`); subcommands `check --root`, `apply`, `snippet`, `decline --root` (calls sibling `spex-setup-profile.py decline-codex-progress` via `sys.executable`); exit codes 0/3/4; `ImportError` on `tomllib` treated as unsupported; handle empty arrays, missing trailing newline, comments after `]`, `[tui.<sub>]` sub-tables and CRLF files (detect and keep the file's line ending); `snippet` falls back to defaults plus `task-progress` when the file cannot be parsed. Make it executable with a `#!/usr/bin/env python3` shebang and module docstring.
- [X] T022 [US3] Create `spex/codex/skills/cc-spex-init/scripts/codex-progress.sh` (POSIX `sh`, executable): resolve the Spex source in the order `SPEX_SOURCE`, `./spex` (when `spex/setup.yml` and `spex/extensions/spex` exist), plugin root four levels above the script dir, mirroring `bootstrap.sh`; find `python3`/`python`; exec `<source>/scripts/spex-codex-progress.py "$@"`; `ERROR:` + exit 1 when source or interpreter is missing.
- [X] T023 [US3] Add a "## Codex progress display" section to `spex/codex/skills/cc-spex-init/SKILL.md` between "Defaults and overrides" and "Report": run only after the bootstrap succeeded and only when the effective integration is `codex` (default, or `--integration codex`); run `sh <skill dir>/scripts/codex-progress.sh check --root "<project root>"`; on `CONFIGURED` or `DECLINED` say nothing; on `ASK` ask one yes/no question ("Add spex ship progress (task progress) to your Codex status line and terminal title? This edits <config path>."); on yes run `apply`, requesting escalation because the file is outside the workspace, then on exit 0 tell the user it takes effect in a new Codex session, and on any non-zero exit or denied escalation show the `snippet` output; on no run `decline --root "<project root>"` and show its hint. No new flag.
- [X] T024 [US3] Check `tests/test_cc_spex_codex_plugin.sh` (and any manifest or file-list checks for the Codex plugin) for assertions about the skill's script files or SKILL.md structure, and update them to include `scripts/codex-progress.sh` and the new section; run `make test-codex-plugin`.

**Checkpoint**: init offers the change once; config edits are minimal and safe.

---

## Phase 7: Polish & Cross-Cutting

- [X] T025 [P] Document Codex ship progress in `README.md` (Codex section: banner + checklist during ship, `Tasks n/8` in footer/title after opting in, manual `/statusline` and `/title` path) and in `spex/docs/help.md` (quick reference note).
- [X] T026 [P] Add a CHANGELOG entry in `CHANGELOG.md` following the existing format (Unreleased / Added).
- [X] T027 Run the full relevant test set: `make test-statusline test-ship-state test-adapt test-codex-progress test-setup-profile test-codex-plugin test-workflow-setup sync-scripts-check`; fix any failure.
- [X] T028 Run quickstart steps 2 and 4 by hand and note the outcome in the quickstart "Results" heading. For step 5 (live Codex run, SC-001/SC-002): if it cannot be run non-interactively in this session, record it as "skipped: manual" with the step-5 instructions; never simulate it.

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → stories.
- T002 must pass before T007 touches the status line. T004 before T009-T012 (empty expansion).
- US1 (T005-T013) is the MVP. US4 (T014-T015) depends on US1 being complete. US2 (T016-T017) depends on T008 and T011. US3 (T018-T024) depends only on Phase 2 and can run in parallel with US1/US2 (different files), except T024 which needs T022/T023.
- Polish after all stories.

## Parallel Opportunities

- T005 and T006 (different test files).
- T018 and T019 (different test files); T020-T022 touch different files and can proceed in parallel once their tests exist.
- T025 and T026.

## Implementation Strategy

1. MVP: Phases 1-3 (banner + checklist in Codex, Claude unchanged by construction).
2. Prove Claude parity (Phase 4).
3. Paused/failed coverage (Phase 5).
4. Footer/title opt-in (Phase 6).
5. Docs, changelog, full test run (Phase 7).
