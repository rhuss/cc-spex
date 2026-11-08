# Research: Ship Progress in Codex

## R1: Where the banner text is rendered (FR-009, FR-010, FR-012)

- **Decision**: Add a `--banner` mode to `spex/scripts/spex-ship-statusline.sh`. In this mode the script resolves the state file exactly as today, skips stdin, the chained status line, the extension list and the context percentage, sets all color variables to empty strings, and prints the ship line followed by a newline. Non-ship modes and missing/unreadable state print nothing (exit 0).
- **Rationale**: The stage icons, the ship prefix, the 9-cell running bar, the paused/failed suffixes and the done line already live in `render_ship`. Reusing that function with blank colors gives one source for both the Claude line and the banner, and the done banner is automatically `🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8`. No Python runs on the Claude per-render hot path (see idea-inbox `statusline-python-per-render`).
- **Alternatives considered**:
  - Banner rendered in `spex-ship-state.py`: duplicates the emoji table and bar logic (violates FR-012), or forces the Claude status line to start Python on every render.
  - Shared icon table in a data file read by both: adds a file and a parser for eight entries; more moving parts than reusing `render_ship`.

## R2: Where the plan steps come from (FR-006a, FR-012)

- **Decision**: Add a `progress` subcommand to `spex-ship-state.py` (via the existing `spex-ship-state.sh` shim). It reads the state file, builds the plan from the existing `STAGES` list, runs the sibling `spex-ship-statusline.sh --banner` (stdin from `/dev/null`) and prints two lines:
  ```
  BANNER <banner text>
  PLAN <JSON array of {"step", "status"}>
  ```
  Missing, unreadable or non-ship state: no output, exit 0.
- **Rationale**: `STAGES` is already the stage order used by `create`/`advance`. One command gives the agent both artifacts, so the Codex instructions only say "run progress, show BANNER, pass PLAN to update_plan". Satisfies Constitution VII (state as scripts).
- **Alternatives considered**: Two separate commands (`banner`, `plan`): two calls per transition for no benefit. Emitting progress from `advance` itself: the script does not know the harness, and Claude must not see extra output change.

## R3: `update_plan` shape and status mapping (FR-001..FR-005)

- **Decision**: `PLAN` is a JSON array of `{"step": "<label>", "status": "pending"|"in_progress"|"completed"}`, the shape of Codex's `update_plan` `plan` argument. For `stage_index = i` and status `running`: steps `< i` completed, `i` in_progress, `> i` pending. Paused/failed: same, with label `"<stage> (paused)"` / `"<stage> (failed)"`. Stage `done` (written by `advance` after `review-code`, status `completed`): all completed. `--start-from` needs no special handling, because `create` writes the start index and earlier steps fall below it.
- **Rationale**: Matches the Codex source (`task-progress` counts completed vs total of the last plan). Labels start with the stage name (FR-006).

## R4: "Claude expands to nothing" in the adapter (FR-016, FR-017a, SC-003)

- **Findings**: `spex-adapt-commands.sh` writes each token to a file with `jq -r`, which appends a newline, so an empty token becomes one blank line. An inline token whose file is empty falls into the fallback branch (`getline` returns 0, same branch as a missing file). A block key with no mapping is left in place.
- **Decision**:
  - Write token files with `jq -j` (no trailing newline). For non-empty values the output is unchanged (awk `getline` reads a final line without newline the same way, and the inline joiner never used the trailing newline).
  - In the inline branch, treat `getline` returning `0` (file exists, empty) as an empty replacement, and only `-1` (file missing) as fallback.
  - Use a block marker `{harness:ship-progress}` / `{/harness:ship-progress}` whose neutral body is empty, placed directly after the last line of an existing paragraph and directly before an existing blank line, so removing the two marker lines restores the original text byte for byte. Claude maps `ship-progress` to `""`.
- **Verification**: an automated test adapts the command tree for Claude twice, once as is and once with the two `ship-progress` marker lines deleted from the ship command, and asserts byte-identical results. A second check (quickstart, run once before merge) adapts the tree from `main` and from the branch with the respective adapter and asserts that only the ship command differs for Codex/OpenCode and nothing differs for Claude, which covers the `jq -j` change.
- **Note**: Installs that never run the adapter (for example the Claude dev install via `spex-init.sh`, where existing `{harness:...}` markers remain raw today) would show the two raw marker lines with nothing between them. Keeping the neutral body empty makes that harmless. This pre-existing gap is out of scope.

## R5: Codex and OpenCode instruction text (FR-007, FR-015, FR-017)

- **Decision**: The Codex token is a short "Progress Reporting (Codex)" subsection placed in "State File Management" right after "Stage Transitions". It states one rule bound to the state commands instead of repeating instructions at every stage: after `create`, `advance`, `pause`, `fail` and `resume`, run `progress`, put the `BANNER` text verbatim as its own line in the reply, call `update_plan` with the `PLAN` array; on `PIPELINE_COMPLETE` run it before anything removes the state file; skip silently on empty output; no other `update_plan` calls in the main thread (inline stage skills included) until `PIPELINE_COMPLETE`. The OpenCode token is the same minus the `update_plan` lines.
- **Rationale**: A single rule tied to the scripted state commands is harder to skip than eight scattered reminders, and it automatically covers resume, start-from and pause paths. The stage list is not hard-coded in the instructions (FR-012).

## R6: Editing the Codex configuration (FR-018..FR-025)

- **Decision**: New canonical script `spex/scripts/spex-codex-progress.py` with subcommands:
  - `check --root <project>` → prints `CONFIGURED` (both lists contain `task-progress`), `DECLINED` (project profile records the decline) or `ASK`.
  - `apply` → edits the config; prints `APPLIED path=<p>` or `UNCHANGED path=<p>`; exit 3 for unparseable/unsupported forms, exit 4 for write failures; in both error cases prints the manual snippet to stdout and the reason to stderr.
  - `snippet` → prints the TOML lines to add and the `/statusline` and `/title` hint.
  - `decline --root <project>` → records the decline through `spex-setup-profile.py` and prints the hint.
  - Config path: `$CODEX_HOME/config.toml` if `CODEX_HOME` is set, else `~/.codex/config.toml`.
- **Editing approach**: line-based edit plus `tomllib` validation (Python 3.11+, read-only parser in the standard library). Steps: parse the whole file with `tomllib` (failure → exit 3); reject inline `tui = {...}`, top-level dotted `tui.*` keys and repeated `[tui]` headers (exit 3); reject `status_line`/`terminal_title` values that are not arrays of strings (exit 3). Within the `[tui]` table region, append `"task-progress"` before the closing `]` of an existing array (single-line: insert `, "task-progress"`; multi-line: insert a new item line with the indentation of the previous item, handling a trailing comma), or add a missing key line at the end of the table's key block with the Codex defaults plus `task-progress`. Without a `[tui]` table, append `\n[tui]\n...` at the end of the file. Re-parse the result with `tomllib` and assert that only the two lists changed and they equal the expected values; otherwise abort without writing (exit 3). Write via temp file + `os.replace` in the same directory, creating the directory if missing.
- **Rationale**: No third-party TOML writer is available (the project avoids dependencies). A line-based edit preserves comments and formatting (FR-021), and the `tomllib` round-trip check gives a hard safety net (SC-004).
- **Alternatives considered**: `tomlkit` (round-trip writer): a new dependency, against the "jq + specify only" constraint. Regex-only editing (like `configure-codex-project.py`): no verification that the result means what we expect.
- **Missing `tomllib`** (Python < 3.11): treat as unsupported (exit 3, manual snippet).

## R7: Recording the decline (FR-024)

- **Decision**: `spex-setup-profile.py` gets an optional field `codex_progress` with the single allowed value `"declined"`. `validate()` accepts and keeps it, `resolve()` carries the stored value forward, and a new subcommand `decline-codex-progress --root <project>` loads the stored profile (or the defaults when absent), sets the field and writes atomically.
- **Rationale**: Every setup run rewrites `.specify/spex.json` through `resolve` → `persist`; a field not in the schema would be rejected or dropped. Keeping all writes in the one script that owns the schema avoids a second writer.

## R8: Where the Codex init skill runs the script (FR-018, FR-019, FR-023)

- **Decision**: Add a wrapper `spex/codex/skills/cc-spex-init/scripts/codex-progress.sh` that resolves the Spex source in the same order as `bootstrap.sh` (`SPEX_SOURCE`, `./spex` in the cc-spex repository, plugin root four levels up) and execs `python3 <source>/scripts/spex-codex-progress.py "$@"`. The skill gets a "Codex progress display" section that runs after a successful bootstrap and before the report, only when the effective integration is `codex`: `check` → ask on `ASK` → `apply` with an escalation request (writes outside the workspace) → on failure or denial show `snippet`; on "no" run `decline`.
- **Rationale**: The question needs the agent (setup.yml cannot read replies back), and `~/.codex` is outside the workspace sandbox, so a `setup.yml` step would fail at the default security level.
- **Claude init** (`spex-init.sh`, `/spex:init`) is not touched (FR-019).

## R9: Codex defaults (FR-020)

- `status_line` default: `["model-with-reasoning", "current-dir", "thread-name"]` (`DEFAULT_STATUS_LINE_ITEMS`, `codex-rs/tui/src/chatwidget.rs`).
- `terminal_title` default: `["activity", "thread-name", "project-name"]` (`DEFAULT_TERMINAL_TITLE_ITEMS`, `codex-rs/tui/src/chatwidget/status_surfaces.rs`).
- Kept as constants in `spex-codex-progress.py` with a comment naming the source files.
