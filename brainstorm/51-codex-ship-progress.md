# Brainstorm: Ship Progress in Codex

**Date:** 2026-10-26
**Status:** ready for spec

## Problem Framing

In Claude Code, a ship run shows where it stands at all times. `spex/scripts/spex-ship-statusline.sh` reads `.specify/.spex-state` and renders a status line such as:

```
🧬 ship 🔨 implement ▓▓▓▓▓▓░░░ 6/8 🧠 [gates, worktrees] | 42%
```

In Codex there is nothing comparable. The user watches a long autonomous pipeline with no indication of which stage it is in or how far along it is.

What Codex offers (verified against Codex CLI 0.164.0 and the `openai/codex` source, `codex-rs/tui/src/chatwidget/status_surfaces.rs`):

- A configurable footer, `[tui].status_line`, and terminal title, `[tui].terminal_title`, both in `~/.codex/config.toml`. Both accept only a fixed set of built-in item ids. There is no item that runs a custom command, so the Claude status line cannot be reproduced 1:1.
- Defaults when the key is unset: `status_line = ["model-with-reasoning", "current-dir", "thread-name"]` and `terminal_title = ["activity", "thread-name", "project-name"]`. Setting a key replaces the defaults.
- The built-in item `task-progress` renders `Tasks {completed}/{total}` from the most recent `update_plan` call in the session. It is omitted until a plan exists. It works in both the footer and the title.
- `update_plan` is the agent's own tool. Calling it also renders the plan as a checklist in the transcript.

## Goal

During a Codex ship run, the user can always see which stage the pipeline is in and how far along it is. Looking the same as the Claude status line is explicitly not a goal; the user accepts a different look as long as the stage and progress are visible.

## Approaches Considered

1. **Drive `update_plan` with the ship stages.** Native: shows up as a checklist in the transcript and as `Tasks n/8` in the footer and title.
2. **Stage banner in the chat.** At each transition, ship prints a one-line plain-text status derived from the same state file. Exact content, but it scrolls away.
3. **External pane (cc-deck/Zellij or tmux) running the existing status line script.** Full 1:1 rendering with colors, but only inside that wrapper.

## Decision

**Approaches 1 and 2 together.** The cc-deck/tmux pane (3) is out of scope.

The footer and title give a persistent count (`Tasks 6/8`), the checklist shows which stage that count refers to, and the banner names the stage explicitly at each transition.

## Key Requirements

### 1. Plan checklist (Codex only)

- At pipeline start (including a resume or `--start-from`), and after every successful `advance`, the ship skill calls `update_plan` with all eight stages in pipeline order: specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code.
- Stages before the current one are `completed`, the current one is `in_progress`, the rest are `pending`. Stages skipped by `--start-from` count as `completed`.
- When the pipeline completes (`advance` outputs `PIPELINE_COMPLETE`), a final `update_plan` marks all eight `completed`.
- On `pause`, `fail`, and `resume`, ship calls `update_plan` again. `update_plan` has no paused/failed state, so the current stage stays `in_progress` with a label suffix: `implement (paused)`, `implement (failed)`. *(Builder's call, settled during review.)*
- From pipeline start until `PIPELINE_COMPLETE`, the main agent must not use `update_plan` for anything else, because `task-progress` reflects only the most recent plan. Worker subagents run in their own threads and are not affected. After `PIPELINE_COMPLETE` the restriction ends: walkthrough, submit, and finish may use `update_plan` for their own steps. *(Builder's call.)*
- Plan step labels are the stage names. The skill may append short context (e.g. `implement (checkpoint 2/3)`) but must keep the stage name first.

### 2. Stage banner (Codex only)

- At the same points (start, each `advance`, `pause`, `fail`, `resume`, completion), ship posts a single plain-text line in its reply, e.g.:

  ```
  🧬 ship 🔨 implement ▓▓▓▓▓▓░░░ 6/8 🧠
  ```

  with `⏸ paused` or `✗ failed` appended when the state says so, and `🧬 ship ✅ done` at completion.
- No ANSI escape codes (Codex renders chat as markdown).
- The banner text is produced by a script from `.specify/.spex-state`, not composed by the model, so stage names, emojis, the progress bar, and the ask-level icon stay consistent with the Claude status line. The stage-to-emoji mapping and bar logic must live in one place (or be shared) rather than being duplicated between the Claude status line and the banner.

### 3. Harness separation

- The ship command (`spex/extensions/spex/commands/speckit.spex.ship.md`) stays harness-neutral. The new behavior goes behind a `{harness:...}` marker that `spex-adapt-commands.sh` resolves per harness.
- Codex: the marker expands to the checklist and banner instructions.
- Claude: the marker expands to nothing. The Claude status line already covers this, and Claude output must not change.
- OpenCode/generic: the builder decides; the banner alone is a reasonable default if it costs nothing extra.

### 4. Setup during Codex init

- The Codex `cc-spex-init` skill asks: add spex progress to the Codex status line and terminal title? The question lives in the skill (agent-driven), not in a `setup.yml` step, because `setup.yml` cannot read an interactive reply back and its shell steps run in the workspace sandbox. *(Builder's call.)*
- Claude init, including `--integration codex` from Claude Code, does not ask. *(Builder's call.)*
- "Asks once" means once per project: a "no" is recorded in `.specify/spex.json` and later inits in that project do not ask again. A yes needs no record, because the presence of `task-progress` in both lists suppresses the question. *(Builder's call.)*
- `~/.codex/` is outside the workspace sandbox, so the agent requests escalation for the write (Codex's approval prompt is the second confirmation). If escalation is denied or the write fails, init prints the TOML lines to add plus the `/statusline` and `/title` hint, and continues. *(Builder's call.)*
- On yes, it edits `~/.codex/config.toml`:
  - If `[tui].status_line` exists, append `"task-progress"` unless already present. Never remove or reorder existing items.
  - If it does not exist, write the Codex defaults listed above plus `"task-progress"`.
  - Same rule for `[tui].terminal_title`.
  - Preserve all other content, comments, and formatting of the file; write atomically.
- On no, print a short hint: use `/statusline` and `/title` in Codex to add "task progress".
- If `task-progress` is already in both lists, do not ask.
- Claude init is unaffected.

### 5. Docs and tests

- README and `spex/docs/help.md`: describe how progress shows up in Codex and the init prompt.
- Tests: adapter output for Codex contains the checklist and banner instructions and Claude output is unchanged; the banner renders correctly for running, paused, failed, and done states; the config edit covers missing `[tui]` table, existing lists with and without `task-progress`, and leaves unrelated content untouched.

## Non-Goals

- A 1:1 visual copy of the Claude status line in Codex.
- An external status pane (cc-deck, Zellij, tmux).
- Flow mode (step-by-step `speckit-*` commands) and watch mode progress in Codex. These may follow later using the same mechanism.
- Showing the quality gate letters (C/S/P/R), extension list, or context percentage in Codex.
- Changing the Claude status line.

## Anti-Goals

- Silently modifying `~/.codex/config.toml` without asking, or replacing a user's existing status line items.
- The model hand-writing the banner so it drifts from the actual state.
- Ship's own use of `update_plan` being clobbered mid-run by the agent planning unrelated steps, leaving the footer showing a wrong count.

## Left to the Builder

- Whether the banner comes from a new plain-output mode of `spex-ship-statusline.sh`, a new `spex-ship-state.sh` subcommand, or extra output from `advance`.
- The marker name(s) and exact instruction wording in the Codex command map.
- How the init edits TOML (e.g. Python with a minimal targeted edit; `tomllib` is read-only).
- Where in the init flow the question is asked.

## Open Questions

- Does Codex honor `[tui]` keys from a trusted project's `.codex/config.toml`? If so, a project-scoped alternative to editing the user's global config may be worth offering later. Not verified.
