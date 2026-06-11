# Tasks: Backpressure Loops

**Input**: Design documents from `specs/024-backpressure-loops/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: No new project structure needed. This feature modifies existing files only.

- [ ] T001 Read existing files to understand current structure: `spex/extensions/spex/commands/speckit.spex.ship.md` (Stage 6 implement subagent prompt), `spex/extensions/spex/commands/speckit.spex.finish.md` (finish command), `spex/scripts/spex-ship-state.sh` (state management), `spex/scripts/spex-ship-statusline.sh` (statusline rendering)

---

## Phase 2: Per-Task Test Checkpoints (US1)

**Goal**: During the ship pipeline's implement stage, run the project's test suite after each task completes and fix failures before proceeding to the next task.
**Independent Test**: Run `/speckit-spex-ship` on a project with a test suite and 3+ tasks. Verify tests run between tasks and that a failure blocks progression.

- [ ] T002 [US1] Add per-task test checkpoint instructions to the Stage 6 implement subagent prompt in `spex/extensions/spex/commands/speckit.spex.ship.md`. The prompt must instruct the agent to: (a) auto-detect the test command using the same logic as verify (Makefile, package.json, go.mod, pytest, cargo), (b) run the test suite after completing each task in tasks.md, (c) if tests fail, attempt to fix within 2 attempts before pausing, (d) read `implement.test_between_tasks` from `.specify/extensions/spex/spex-config.yml` via `yq` and skip checkpoints if set to `false`
- [ ] T003 [US1] Commit and verify the ship.md changes render correctly when read by Claude Code (no markdown parsing issues with the expanded prompt)

---

## Phase 3: Watch Mode State Management (US4)

**Goal**: Extend state management scripts and statusline to support `mode: "watch"` with PR number, timeout, CI status tracking.
**Independent Test**: Manually create a watch state file and verify the statusline renders it correctly.

- [ ] T004 [P] [US4] Add `watch-start` command to `spex/scripts/spex-ship-state.sh` that creates/updates the state file with `mode: "watch"` and watch-specific fields: `pr_number`, `pr_url`, `watch_started_at`, `watch_timeout_minutes` (default 30), `watch_poll_interval_seconds` (default 60), `last_ci_status` ("pending"), `ci_fix_attempts` (0), `last_triage_at` (null), `triage_count` (0), `feature_branch`
- [ ] T005 [P] [US4] Add `watch-update` command to `spex/scripts/spex-ship-state.sh` that accepts key-value pairs and updates watch-specific fields in the state file (e.g., `watch-update last_ci_status passing ci_fix_attempts 1`)
- [ ] T006 [P] [US4] Add `watch-cleanup` command to `spex/scripts/spex-ship-state.sh` that removes the state file and outputs `WATCH_COMPLETE`
- [ ] T007 [US4] Add watch mode rendering to `spex/scripts/spex-ship-statusline.sh`: when `mode` is `"watch"`, render PR number, elapsed time since `watch_started_at`, last CI status with color coding (green=passing, red=failing, yellow=pending), and triage count if > 0. Format: `👀 PR #42 | 5m | CI ✓ | T:2`

---

## Phase 4: Post-PR Watch Mode (US2, US3)

**Goal**: Add `--watch` flag to finish command that monitors CI and optionally invokes collab triage after PR creation.
**Independent Test**: Run `/speckit-spex-finish --watch` on a project with CI configured and verify it monitors and reports CI status.

- [ ] T008 [US2] Add `--watch` argument parsing to `spex/extensions/spex/commands/speckit.spex.finish.md`: parse `--watch` flag from arguments, read `watch.timeout_minutes` and `watch.poll_interval_seconds` from `.specify/extensions/spex/spex-config.yml` via `yq` with defaults (30 and 60)
- [ ] T009 [US2] Add watch mode entry point in finish command after PR creation (Phase 5, Options B1 and B2): instead of cleaning up state immediately, invoke the state script's `watch-start` command with PR number, URL, timeout, and interval. Then enter the watch loop described in T010
- [ ] T010 [US2] Implement the watch loop in the finish command. Each iteration: (a) check if timeout expired via `watch_started_at` + `watch_timeout_minutes`, exit if expired, (b) check PR state via `gh pr view --json state`, exit if closed/merged, (c) poll CI via `gh pr checks <PR>`, (d) if all checks pass and no pending comments (or collab not enabled), run `watch-cleanup` and exit success, (e) if checks failing, read failure log via `gh run view <RUN_ID> --log-failed`, attempt fix, commit, push, increment `ci_fix_attempts` via `watch-update`, (f) if `ci_fix_attempts >= 2`, pause and report, (g) schedule next poll via ScheduleWakeup with the configured interval
- [ ] T011 [US2] Handle the initial CI wait: after PR creation, CI checks may not appear immediately. The first poll should wait up to 5 minutes (5 polls at 60s interval) for checks to appear before reporting "No CI checks detected" and exiting
- [ ] T012 [US3] Add collab triage integration to the watch loop: after CI passes, check if spex-collab is enabled via `.specify/extensions/.registry`, if enabled check for new comments since `last_triage_at` via `gh api repos/{owner}/{repo}/pulls/{pr}/comments`, if new comments exist invoke `/speckit-spex-collab-triage --pr <number>`, update `last_triage_at` and `triage_count` via `watch-update`
- [ ] T013 [US3] When spex-collab is NOT enabled but comments exist, report the count and suggest enabling spex-collab. Do not attempt triage
- [ ] T014 [US2] Add `--watch` pass-through in `spex/extensions/spex/commands/speckit.spex.ship.md`: in Stage 8 (finish), when `create_pr` is true in the state file, add `--watch` to the finish subagent prompt

---

## Phase 5: Polish & Cross-Cutting

**Purpose**: Documentation updates and edge case handling.

- [ ] T015 Update `README.md`: add `--watch` flag to the finish command entry in the Commands Reference table, add per-task test checkpoint description to the ship workflow section
- [ ] T016 Update `spex/docs/help.md`: add `--watch` to finish quick reference, add `implement.test_between_tasks` and `watch.*` config keys
- [ ] T017 [P] Handle edge case in finish: when `--watch` is used without a PR (direct merge to default branch), warn "Watch mode requires a PR. Ignoring --watch." and proceed with normal finish behavior

---

## Dependencies

```
T001 → T002, T004, T005, T006 (read existing files first)
T002 → T003 (verify after writing)
T004, T005, T006 → T007 (state commands before statusline)
T007, T008 → T009 (state + parsing before watch entry)
T009 → T010 (entry point before loop)
T010 → T011, T012, T013 (loop before edge cases)
T010 → T014 (loop before ship pass-through)
T012, T013, T014 → T015, T016 (features before docs)
```

## Parallel Opportunities

- **T004, T005, T006**: All modify `spex-ship-state.sh` but add independent commands (different functions). Can be written sequentially in one pass or parallelized.
- **T002 and T004-T006**: Phase 2 (test checkpoints) and Phase 3 (state management) are fully independent.
- **T015, T016, T017**: Polish tasks are independent of each other.

## Implementation Strategy

**MVP**: Phase 2 (per-task test checkpoints in ship) delivers immediate value with minimal changes (one file modified). Ship this first.

**Incremental delivery**:
1. Phase 2 (US1): Test checkpoints - single file change, highest impact
2. Phase 3 (US4): State management - infrastructure for watch mode
3. Phase 4 (US2, US3): Watch mode - depends on Phase 3
4. Phase 5: Documentation - after all features land
