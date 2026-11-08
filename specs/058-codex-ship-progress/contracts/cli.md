# CLI Contracts: Ship Progress in Codex

All commands exit 0 unless stated. Error text goes to stderr prefixed `ERROR:`.

## `spex-ship-state.sh progress`

- Env: `SHIP_STATE_FILE` (default `.specify/.spex-state`).
- Output (ship state present):
  ```
  BANNER 🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠
  PLAN [{"step": "specify", "status": "completed"}, ..., {"step": "review-code", "status": "pending"}]
  ```
  `PLAN` is compact single-line JSON with exactly 8 entries in `STAGES` order.
- Output (missing, unreadable, invalid JSON, or `mode` not `ship`): nothing, exit 0.
- If the banner script is missing or prints nothing, the `BANNER` line is omitted and `PLAN` is still printed.

## `spex-ship-statusline.sh --banner`

- Env: `SHIP_STATE_FILE`; otherwise resolves `.specify/.spex-state` at the git root of `$PWD` (same as today).
- Does not read stdin, does not run the chained status line, prints no extension list and no context percentage, emits no escape sequences.
- Output: one ship line plus newline (see data-model.md banner table), or nothing.
- Without `--banner`: behavior and bytes unchanged for all inputs.

## `spex-setup-profile.py decline-codex-progress --root <abs project dir>`

- Loads `.specify/spex.json` (defaults if absent), sets `"codex_progress": "declined"`, writes atomically, prints the resulting declaration.
- Errors: invalid root or invalid stored profile → `ERROR:` and exit 1/2 (same as other subcommands).
- `validate`, `resolve`, `persist` accept and preserve `codex_progress` (only value `"declined"`; any other value → validation error).

## `spex-codex-progress.py`

Config path: `$CODEX_HOME/config.toml` when `CODEX_HOME` is set, else `~/.codex/config.toml`.

| Subcommand | Output | Exit |
|------------|--------|------|
| `check --root <dir>` | `CONFIGURED` if both lists contain `task-progress`; else `DECLINED` if `<dir>/.specify/spex.json` has `codex_progress: declined`; else `ASK` | 0 |
| `apply` | `APPLIED path=<p>` or `UNCHANGED path=<p>` | 0 |
| `apply` (unparseable / unsupported form / no `tomllib`) | reason on stderr, snippet on stdout, file untouched | 3 |
| `apply` (write failed, e.g. sandbox denied) | reason on stderr, snippet on stdout | 4 |
| `snippet` | TOML lines to add (full `[tui]` keys with current items plus `task-progress`; defaults plus `task-progress` when a key is missing or the file cannot be parsed) followed by the hint line | 0 |
| `decline --root <dir>` | calls `spex-setup-profile.py decline-codex-progress`, then prints the hint line | 0 (1 if recording failed; hint still printed) |

Hint line (exact): `To show spex progress later, run /statusline and /title in Codex and add "task progress".`

A config with `status_line` present but not `terminal_title` (or vice versa) counts as `ASK` until both contain `task-progress`; `apply` changes only what is missing.

## `cc-spex-init/scripts/codex-progress.sh <subcommand> [args]`

Resolves the Spex source like `bootstrap.sh` (`SPEX_SOURCE`, `./spex`, plugin root) and execs `python3 <source>/scripts/spex-codex-progress.py <subcommand> [args]`. Exit codes pass through; exit 1 with `ERROR:` if no source or no Python is found.

## Command map tokens: `ship-progress` (block marker)

| Harness | Expansion |
|---------|-----------|
| claude | empty (no lines) |
| codex | "Progress Reporting (Codex)" subsection: run `progress` after every state command, show `BANNER` verbatim, call `update_plan` with `PLAN`, run before state removal on `PIPELINE_COMPLETE`, skip on empty output, no other `update_plan` in the main thread (inline stage skills included) until `PIPELINE_COMPLETE` |
| opencode | same without the `update_plan` parts |
| generic (no map) | markers stay as written, neutral body is empty |
