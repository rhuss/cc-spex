# Feature Specification: Ship Progress in Codex

**Feature Branch**: `058-codex-ship-progress`

**Created**: 2026-10-26

**Status**: Draft

**Input**: Brainstorm `brainstorm/51-codex-ship-progress.md`: show where a ship pipeline stands while it runs in Codex, keeping the spirit of the Claude Code status line without copying its look.

## Background

In Claude Code, a ship run shows its stage and progress at all times through the spex status line (for example `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`). Codex has no equivalent: a user watching a long autonomous ship pipeline cannot tell which stage it is in or how far along it is.

Codex (verified against Codex CLI 0.164.0 and its source) offers:

- A configurable footer (`[tui].status_line`) and terminal title (`[tui].terminal_title`) in the user's Codex configuration (`~/.codex/config.toml`). Both accept only a fixed set of built-in item identifiers; there is no item that runs a custom command.
- Built-in defaults when a key is unset: footer `["model-with-reasoning", "current-dir", "thread-name"]`, title `["activity", "thread-name", "project-name"]`. Setting a key replaces the defaults entirely.
- A built-in item `task-progress` that shows `Tasks {completed}/{total}` from the agent's most recent plan update (the `update_plan` tool), omitted until a plan exists. It works in both the footer and the title.
- The agent's plan update also renders as a checklist in the conversation.

## Clarifications

### Session 2026-10-26

- Q: At what point in Codex init is the footer/title question asked? → A: After the bootstrap succeeded, before the final report; never when the bootstrap failed.
- Q: Which forms of the Codex configuration may setup edit? → A: Only keys inside a single `[tui]` table whose values are arrays of strings (single- or multi-line); any other form (inline `tui = {...}`, dotted `tui.status_line` at top level, `[tui]` repeated) is left untouched and handled like an unparseable file.
- Q: Should Codex init get a new flag to pre-answer or skip the question? → A: No new flag; the question is asked at most once per project.
- Q: Does Codex init ask when the user passes a non-Codex integration (e.g. `--integration claude`)? → A: No; ask only when the effective integration is `codex`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See the current stage while a Codex ship run is in progress (Priority: P1)

A developer starts `speckit-spex-ship` in Codex and switches attention elsewhere. Whenever they look back at the conversation, they see a checklist of the eight pipeline stages with finished stages ticked and the current stage marked as in progress. Each time the pipeline moves to a new stage, a one-line status banner naming the stage and the progress (for example `🧬 ship 🔨 implement ▓▓▓▓▓▓▓░░ 7/8 🧠`) appears in the conversation.

**Why this priority**: This is the core need. Without it, the user has no idea where a long autonomous run stands. It works without any configuration change.

**Independent Test**: Install the Codex variant of the ship command, run a ship pipeline (or simulate stage transitions against a state file), and confirm the checklist and banner appear at start and after each stage transition with correct stage and count.

**Acceptance Scenarios**:

1. **Given** a fresh ship run in Codex, **When** the pipeline starts at `specify`, **Then** the conversation shows an eight-step checklist (specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code) with `specify` in progress and the rest pending, and a banner showing `specify` and `1/8`.
2. **Given** a ship run at `plan`, **When** the stage completes and the pipeline advances, **Then** the checklist shows specify through plan completed and `tasks` in progress, and a banner showing `tasks` and `5/8` appears.
3. **Given** a ship run started with `--start-from implement`, **When** the pipeline starts, **Then** the six stages before `implement` show as completed and `implement` as in progress.
4. **Given** a ship run at `review-code`, **When** the pipeline completes, **Then** all eight checklist steps are completed and a banner showing the pipeline as done appears.

---

### User Story 2 - See paused or failed state at a glance (Priority: P2)

When a review stage pauses the pipeline for the user's input, or a stage fails, the developer immediately sees which stage stopped and why it is waiting, both in the checklist and in a banner. When they reply and the pipeline resumes, the indicators return to normal.

**Why this priority**: A paused pipeline waiting for input is the moment the user most needs to notice. It builds on Story 1.

**Independent Test**: Put a state file into paused, failed, and resumed states and confirm the banner and the checklist instructions produce the expected labels.

**Acceptance Scenarios**:

1. **Given** a ship run at `review-spec`, **When** the pipeline pauses for user input, **Then** the checklist shows `review-spec (paused)` as the current step and a banner ending in `⏸ paused` appears.
2. **Given** a ship run at `implement`, **When** the stage fails, **Then** the checklist shows `implement (failed)` and a banner ending in `✗ failed` appears.
3. **Given** a paused pipeline, **When** the user replies and the pipeline resumes, **Then** the checklist shows the stage name without the suffix and a banner without the paused marker appears.

---

### User Story 3 - See progress in the Codex footer and terminal title (Priority: P2)

During Codex project setup, the developer is asked once whether spex progress should be added to the Codex footer and terminal title. After agreeing, the footer and the terminal tab show `Tasks n/8` during ship runs, so progress is visible even when the conversation is scrolled or the window is in the background.

**Why this priority**: Gives persistent, glanceable progress, but depends on a change to the user's global Codex configuration, which must be opt-in.

**Independent Test**: Run the configuration step against sample Codex configuration files (no `[tui]` table, existing lists with and without `task-progress`) and confirm the resulting files.

**Acceptance Scenarios**:

1. **Given** a Codex configuration with `[tui].status_line = ["model-with-reasoning", "git-branch"]`, **When** the user agrees, **Then** the list becomes `["model-with-reasoning", "git-branch", "task-progress"]` and nothing else in the file changes.
2. **Given** a Codex configuration with no `status_line` and no `terminal_title`, **When** the user agrees, **Then** both keys are written with the Codex defaults followed by `task-progress`.
3. **Given** a Codex configuration where both lists already contain `task-progress`, **When** Codex setup runs, **Then** the user is not asked.
4. **Given** the user declines, **When** Codex setup runs again later in the same project, **Then** the user is not asked again, and setup showed a hint on how to add "task progress" manually via `/statusline` and `/title`.
5. **Given** the user agrees but the write to the Codex configuration is not permitted, **When** setup continues, **Then** it shows the exact configuration lines to add plus the manual hint, and setup completes.

---

### User Story 4 - Claude Code behavior is unchanged (Priority: P1)

A developer using spex in Claude Code sees exactly the same ship command and status line as before. No checklist instructions, banners, or setup questions are added for Claude.

**Why this priority**: Regressions in the primary harness are unacceptable.

**Independent Test**: Generate the Claude variant of the ship command before and after the change and compare; run Claude init and confirm no new question.

**Acceptance Scenarios**:

1. **Given** the harness-neutral ship command, **When** it is adapted for Claude, **Then** the output contains no checklist or banner instructions and is otherwise identical to the output before this feature.
2. **Given** spex init from Claude Code (including with the Codex integration selected), **When** it runs, **Then** it does not ask about the Codex footer or title and does not touch the Codex configuration.

### Edge Cases

- The state file is missing or unreadable when a banner is requested: no banner is shown and the pipeline continues (the banner never blocks the pipeline).
- The state file holds an unknown stage name: the banner shows the stage with a generic icon rather than failing.
- The pipeline is resumed in a new Codex session: the first action after resuming re-establishes the checklist from the state file, so `Tasks n/8` is correct again.
- The main agent wants to plan its own sub-steps during a run: not allowed until the pipeline completes, because the footer count reflects only the most recent plan. Worker subagents run in their own threads and may plan freely.
- After the pipeline completes, follow-up commands (walkthrough draft, submit, finish) may use plan updates for their own steps; the footer then reflects those.
- The Codex configuration file does not exist: on agreement, it is created with only the `[tui]` keys.
- The Codex configuration has a `[tui]` table with other keys (for example `terminal_title` set but `status_line` absent): only the missing key is added with defaults, existing keys are appended to, other keys are untouched.
- The Codex configuration cannot be parsed, or defines `[tui]` keys in an unsupported form (inline table, dotted keys, repeated table): setup does not modify it, shows the manual lines and hint, and continues.
- The bootstrap fails, or the user runs Codex init with a non-Codex integration: the footer/title question is not asked.
- `task-progress` is present in one list but not the other: the user is asked, and on agreement only the missing list is changed.
- The project's spex settings file is missing when recording a decline: it is created with the decline recorded; if that write fails, setup shows the hint and completes.

## Requirements *(mandatory)*

### Functional Requirements

**Plan checklist (Codex only)**

- **FR-001**: In Codex, the ship pipeline MUST publish a plan of all eight stages in pipeline order (specify, clarify, review-spec, plan, tasks, review-plan, implement, review-code) at pipeline start, including fresh start, `--resume`, and `--start-from`.
- **FR-002**: After every successful stage advance, the pipeline MUST publish the plan again with stages before the current one marked completed, the current stage in progress, and later stages pending.
- **FR-003**: Stages skipped by `--start-from` MUST be shown as completed.
- **FR-004**: When the pipeline completes, the pipeline MUST publish the plan with all eight stages completed, and MUST do so (together with the done banner) before anything removes the ship state file.
- **FR-005**: On pause, fail, and resume, the pipeline MUST publish the plan again; for pause and fail the current stage label MUST carry the suffix ` (paused)` or ` (failed)`, and after resume the suffix MUST be gone.
- **FR-006**: Each plan step label MUST start with the stage name; short context MAY follow it.
- **FR-006a**: The plan steps and their statuses MUST be produced by the same spex script as the banner, from the ship state file, so the agent passes them to the plan update as given rather than deriving them itself.
- **FR-007**: The Codex ship instructions MUST tell the main agent, including stage skills that run inline in the main thread (specify, clarify, plan, tasks), not to publish any other plan from pipeline start until completion. After completion this restriction ends. Because the plan is published again at every stage change, a stray plan is corrected at the next transition.

**Stage banner (all harnesses except Claude)**

- **FR-008**: At each point listed in FR-001, FR-002, FR-004, and FR-005, the pipeline MUST show a single-line status banner in its reply.
- **FR-009**: The banner text MUST be produced deterministically by a spex script from the ship state file, not composed by the model. The pipeline instructions MUST tell the agent to show the script output verbatim.
- **FR-010**: The banner MUST contain the stage icon, stage name, a progress bar, `n/8`, and the oversight-level icon, matching the content of the Claude ship status line; it MUST append `⏸ paused` or `✗ failed` when the state says so. At completion the banner MUST be exactly `🧬 ship ✅ done ▓▓▓▓▓▓▓▓ 8/8`, the same text as the Claude done line without colors (the Claude line's 8-cell bar is kept as is).
- **FR-011**: The banner MUST NOT contain terminal color or control codes.
- **FR-012**: Stage icons and progress-bar logic MUST have a single source shared by the Claude status line and the banner, so the two cannot drift apart. Stage order MUST come from the existing stage list of the ship state script; the Codex instructions MUST NOT hard-code the stage list beyond naming it for the reader. The rendered Claude status line MUST stay byte-identical for every state.
- **FR-013**: If the state file is missing, unreadable, or not in ship mode (flow or watch), the banner script MUST produce no output and exit successfully. The same applies to the plan-steps output of FR-006a.

**Harness separation**

- **FR-014**: The harness-neutral ship command MUST express the checklist and banner behavior through harness markers resolved when the command is adapted for a harness.
- **FR-015**: For Codex, the markers MUST expand to the checklist and banner instructions.
- **FR-016**: For Claude, the markers MUST expand to nothing, and the adapted Claude ship command MUST be identical to its output before this feature.
- **FR-017**: For OpenCode, the markers MUST expand to the banner instructions only. Harnesses without a command map (generic) stay neutral, as today.
- **FR-017a**: The adapter MUST support a marker that expands to nothing without leaving blank lines or a fallback note, so FR-016 holds.

**Codex footer and title setup**

- **FR-018**: The Codex init skill MUST ask the user once whether to add spex progress to the Codex footer and terminal title, unless `task-progress` is already present in both lists. The question MUST be asked only after the bootstrap succeeded and before the final report, and only when the effective integration is `codex`. No new init flag is added for it.
- **FR-019**: Claude init, including runs that select the Codex integration, MUST NOT ask this question or modify the Codex configuration.
- **FR-020**: On agreement, for each of `[tui].status_line` and `[tui].terminal_title`: if the key exists, `task-progress` MUST be appended unless already present, without removing or reordering existing items; if the key is missing, it MUST be written as the Codex default list followed by `task-progress`.
- **FR-021**: The configuration change MUST preserve all other content of the file, including comments and formatting, and MUST be written atomically. A missing `[tui]` table MUST be appended at the end of the file; a missing file (and missing directory) MUST be created. The configuration file is `$CODEX_HOME/config.toml` when `CODEX_HOME` is set, otherwise `~/.codex/config.toml`.
- **FR-022**: Setup MUST edit only keys inside a single `[tui]` table whose values are arrays of strings (single- or multi-line). If the file cannot be parsed, or the keys use any other form (inline `tui = {...}`, dotted `tui.*` keys outside the table, a repeated `[tui]` table), the change MUST NOT be made; setup MUST show the manual lines and hint instead.
- **FR-023**: The change MUST be requested through Codex's normal approval for writes outside the workspace. If the write is denied or fails, setup MUST show the exact lines to add plus the `/statusline` and `/title` hint and continue. Nothing is recorded in that case, so the next Codex init asks again (intended: the user wanted the change).
- **FR-024**: On decline, setup MUST record the decline in the project's spex settings (`.specify/spex.json`) and MUST show the `/statusline` and `/title` hint. Later Codex init runs in that project MUST NOT ask again. The project settings schema MUST accept this optional decline field, and every setup run (validate, resolve, persist) MUST keep it, so a refresh neither rejects nor erases it.
- **FR-025**: The configuration change MUST be implemented as a spex script that can be run and tested on its own, with a mode that reports whether the question is needed without changing anything.

**Docs and tests**

- **FR-026**: README and `spex/docs/help.md` MUST describe how ship progress appears in Codex and the setup question.
- **FR-027**: Automated tests MUST cover: Codex adapter output contains the checklist and banner instructions, including the FR-007 instruction; OpenCode adapter output contains the banner instructions only; the project settings keep the decline field across a setup refresh; Claude adapter output is unchanged; the Claude status line output is unchanged for running, paused, failed, and done states; the banner and plan steps for running, paused, failed, `--start-from`, and done states, and for a missing or non-ship state file; the configuration change for a missing file, a missing `[tui]` table, existing lists with and without `task-progress`, a partial `[tui]` table, an unparseable file, the unsupported forms of FR-022 (inline table, dotted keys, repeated table), `CODEX_HOME`, and preservation of unrelated content.

### Key Entities

- **Ship state**: The existing pipeline state file (`.specify/.spex-state`) with stage, stage index, total stages, oversight level, and status (running, paused, failed). Source of truth for the banner and the checklist.
- **Stage definition**: The ordered list of the eight stages with their icons. Shared by the Claude status line and the banner.
- **Codex configuration**: The user's global Codex settings, of which only the `[tui].status_line` and `[tui].terminal_title` lists are touched.
- **Project spex settings**: `.specify/spex.json`, which records a declined setup question for the project.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In a Codex ship run, the current stage is visible in the conversation within one reply of every stage transition, pause, fail, resume, and completion (all 8 stages plus each state change, no gaps).
- **SC-002**: With the footer opted in, the footer and terminal title show a progress count that matches the pipeline's stage at every transition.
- **SC-003**: The adapted Claude ship command is byte-identical to its pre-feature output.
- **SC-004**: For every tested Codex configuration input, the only difference after the change is the added `task-progress` entries (or the added default lists); zero other lines change.
- **SC-005**: A user who declines is asked at most once per project.

## Assumptions

- The Codex agent in a ship run has the `update_plan` tool available, as in Codex CLI 0.164.0.
- `task-progress` reflects only the main thread's plan; subagent plans do not affect it.
- Codex's default footer and title lists are as listed in Background; if Codex changes them, the defaults written by setup may lag until spex is updated.
- Whether Codex honors `[tui]` keys in a trusted project's `.codex/config.toml` is unverified; this feature only edits the user's global configuration.
- Flow mode (step-by-step `speckit-*` commands) and watch mode are out of scope; the same mechanism may be applied later.
- The gate letters, extension list, and context percentage from the Claude status line are not shown in Codex.
- The cc-deck/tmux external pane is out of scope.
