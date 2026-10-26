# Data Model: Ship Progress in Codex

## Ship state (existing, `.specify/.spex-state`)

Read-only for this feature. Written by `spex-ship-state.py`.

| Field | Type | Used for |
|-------|------|----------|
| `mode` | `"ship"` (others ignored) | Banner and plan only render for `ship` (legacy files without `mode` but with `stage` count as ship, as in the status line today) |
| `stage` | one of `STAGES` or `"done"` | Current step label, icon |
| `stage_index` | int 0..8 | Completed/in-progress split; display index `stage_index + 1` |
| `total_stages` | int (8) | Bar and `n/8` |
| `ask` | `always` / `smart` / `never` | Oversight icon |
| `status` | `running` / `paused` / `failed` / `completed` | Suffix (`⏸ paused`, `✗ failed`, `(paused)`, `(failed)`) |

State transitions (unchanged): `create` → running at start index; `advance` → next stage running, after `review-code` → `stage: done, stage_index: 8, status: completed`; `pause` → paused; `fail` → failed; `resume` → running.

## Progress output (new, `spex-ship-state.sh progress`)

Two lines on stdout, or nothing:

```
BANNER <single line, no ANSI>
PLAN [{"step": "<label>", "status": "pending|in_progress|completed"}, ... 8 entries]
```

Plan rules for state `(stage_index = i, status = s)`:

| Condition | step `j < i` | step `j == i` | step `j > i` |
|-----------|--------------|---------------|--------------|
| `s = running` | completed, `STAGES[j]` | in_progress, `STAGES[i]` | pending |
| `s = paused` | completed | in_progress, `STAGES[i] + " (paused)"` | pending |
| `s = failed` | completed | in_progress, `STAGES[i] + " (failed)"` | pending |
| `stage = done` | all completed | | |

## Banner (new mode of `spex-ship-statusline.sh --banner`)

Same text as the Claude ship line without colors, extensions and context:

| State | Banner |
|-------|--------|
| running `implement` (index 6, smart) | `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠` |
| paused `review-spec` (index 2, smart) | `🧬 ship 🔬 review-spec ▓▓▓░░░░░░ 3/8 🧠 ⏸ paused` |
| failed `implement` | `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠 ✗ failed` |
| done | `🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8` |
| missing / unreadable / non-ship | (no output) |

## Project spex settings (extended, `.specify/spex.json`)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schema_version`, `harness`, `extensions`, `security` | existing | yes | unchanged |
| `codex_progress` | `"declined"` | no | Set by `decline-codex-progress`; kept by `validate`, `resolve`, `persist` |

## Codex configuration (external, `$CODEX_HOME/config.toml` or `~/.codex/config.toml`)

Only two keys are touched, inside a single `[tui]` table:

| Key | Default when missing | Change |
|-----|----------------------|--------|
| `status_line` | `["model-with-reasoning", "current-dir", "thread-name"]` | append `"task-progress"` unless present |
| `terminal_title` | `["activity", "thread-name", "project-name"]` | append `"task-progress"` unless present |

Unsupported forms (no change, manual snippet): unparseable file, inline `tui = {...}`, top-level dotted `tui.*` keys, repeated `[tui]` header, non-array or non-string values, Python without `tomllib`.
