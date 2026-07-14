# Tasks: Codex Integration for Deep Review

**Input**: Design documents from `specs/041-codex-deep-review/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Foundational (Harness Adapter Updates)

**Purpose**: Set up the harness marker tokens so the Codex block is included/excluded per adapter

**Critical**: These must be complete before the deep-review command can reference the marker block

- [X] T002 [P] Add `codex-review-tool` token to Claude adapter command-map at `spex/scripts/adapters/claude/command-map.json`. The token value is a short descriptive string (e.g., `"Include Codex external tool detection and dispatch"`), following the pattern of existing tokens like `parallel-dispatch`. The actual Codex detection/invocation code lives in the deep-review command file between `{harness:codex-review-tool}...{/harness:codex-review-tool}` markers, not in the token value.
- [X] T003 [P] Add `codex-review-tool` token to OpenCode adapter command-map at `spex/scripts/adapters/opencode/command-map.json` with the same descriptive token value as Claude adapter. **Note**: The OpenCode adapter currently has an empty `tokens: {}` object. Other deep-review harness tokens (e.g., `parallel-dispatch`, `spawn-worker`) are also absent, meaning OpenCode already strips those blocks. Adding `codex-review-tool` is consistent with adding Codex support, but OpenCode's overall deep-review support is limited by the missing tokens. This is a pre-existing condition, not in scope for this feature.
- [X] T004 Verify Codex adapter command-map at `spex/scripts/adapters/codex/command-map.json` does NOT include `codex-review-tool` token (recursion guard, no changes needed if absent)

**Checkpoint**: Harness adapters ready. The adapt-commands script will now include/exclude the Codex block per harness.

---

## Phase 2: User Story 1 - Codex review runs during deep review (Priority: P1) MVP

**Goal**: When Codex CLI is installed and enabled, deep review invokes it and merges findings into the common schema

**Independent Test**: Run deep review on a branch with Codex installed. Verify "Codex (external)" row appears in the agent summary table.

### Interfaces (shared state across tasks in this phase)

All tasks modify a single file: `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

| Variable / Entity | Produced by | Consumed by | Pattern |
|---|---|---|---|
| `DEFAULT_CODEX` | T005 | T006 | Config default from `yq -r '.external_tools.codex // true'`, same pattern as `DEFAULT_CODERABBIT` |
| `codex` (resolved setting) | T005 | T006, T007 | Resolved external tool setting variable, same pattern as `coderabbit` |
| `CODEX_AVAILABLE` | T006 | T007, T008 | Set to `true` when `which codex` succeeds and config is enabled |
| Codex findings | T007 | T008 | Findings normalized to common schema with `source_agent = "codex"`, `confidence = 75` |
| `CODEX_STATUS` | T007, T009, T010 | T008 | Status string: "completed", "skipped (CLI not installed)", "skipped (disabled in config)", "failed (reason)" |

### Implementation for User Story 1

- [X] T005 [US1] Add Codex config resolution in Step 2 (External Tool Settings Resolution) of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: add `codex: true` to the `external_tools:` section of `spex/extensions/spex-deep-review/config-template.yml`, then read the key with `DEFAULT_CODEX=$(yq -r '.external_tools.codex // true' "$DEEP_REVIEW_CONFIG" 2>/dev/null)` and set `codex = DEFAULT_CODEX` alongside `coderabbit` and `copilot` resolution
- [X] T006 [US1] Add Codex CLI detection in Step 2 (Detect External Tools) of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`, using `which codex >/dev/null 2>&1`, wrapped in `{harness:codex-review-tool}...{/harness:codex-review-tool}` markers. Set `CODEX_AVAILABLE=true` when detected (following the `CODERABBIT_AVAILABLE` pattern)
- [X] T007 [US1] Add Codex invocation section in Step 4 (Dispatch External Tools) of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: invoke `codex review --base $MAIN_BRANCH`, parse output, normalize to common finding schema with `source_agent = "codex"`, `confidence = 75`. Set `CODEX_STATUS = "completed"` on success with finding counts.
- [X] T008 [US1] Add "Codex (external)" row to the agent summary table in Step 9 (Report Gate Outcome) of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`. Display found/fixed/remaining counts and `CODEX_STATUS`.

**Checkpoint**: Deep review now detects, invokes, parses, and reports Codex findings.

---

## Phase 3: User Story 2 - Codex skipped when unavailable (Priority: P1)

**Goal**: Deep review gracefully handles missing/disabled Codex without errors

**Independent Test**: Run deep review without Codex CLI. Verify completion without errors and "skipped" status in the table.

### Implementation for User Story 2

- [X] T009 [US2] Add skip-when-disabled logic in the Codex detection block: when `external_tools.codex` is `false`, skip detection entirely and set status to "skipped (disabled in config)" in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`
- [X] T010 [US2] Add error handling for Codex invocation failures (timeout, auth failure, crash) in Step 4 of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: log failure, continue review, set status to "failed" with reason

**Checkpoint**: Deep review handles all Codex-unavailable scenarios gracefully.

---

## Phase 4: User Story 3 - Recursion guard when running inside Codex (Priority: P1)

**Goal**: The Codex external tool block is absent when spex runs inside the Codex harness

**Independent Test**: Run `spex-adapt-commands.sh codex` on the deep-review command and verify the Codex detection/dispatch block is stripped.

### Implementation for User Story 3

- [X] T011 [US3] Verify that the `{harness:codex-review-tool}...{/harness:codex-review-tool}` block in the deep-review command is correctly stripped by `spex-adapt-commands.sh` when using the Codex adapter (the block is omitted because the Codex command-map has no `codex-review-tool` token)

**Checkpoint**: Recursion guard verified. Codex adapter strips the Codex block.

---

## Phase 5: User Story 4 - Codex re-review during fix loop (Priority: P2)

**Goal**: After fixes are applied, Codex re-reviews only uncommitted changes

**Independent Test**: Trigger a fix loop with a Codex finding and verify `codex review --uncommitted` is invoked on re-review.

### Implementation for User Story 4

- [X] T012 [US4] Add Codex re-review invocation in Step 7 (Autonomous Fix Loop) of `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: use `codex review --uncommitted` for fix-loop re-review rounds, parse and merge findings using standard dedup logic

**Checkpoint**: Fix loop correctly re-invokes Codex with narrowed scope.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Ship pipeline integration and documentation

- [X] T013 [P] Add `--codex` and `--no-codex` flags to the ship pipeline external tool flag resolution in `spex/extensions/spex/commands/speckit.spex.ship.md`
- [X] T014 [P] Update documentation: add Codex to the external tools list in `README.md` and `spex/docs/help.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Foundational)**: No dependencies, start immediately
- **Phase 2 (US1)**: Depends on Phase 1 for harness markers to be available. T005 also adds the config key to config-template.yml.
- **Phase 3 (US2)**: Depends on Phase 2 (adds handling to the detection block created in US1)
- **Phase 4 (US3)**: Depends on Phase 2 (verifies the markers added in US1)
- **Phase 5 (US4)**: Depends on Phase 2 (extends the invocation added in US1)
- **Phase 6 (Polish)**: Depends on Phase 2 for the feature to exist

### Parallel Opportunities

- T002 and T003 can run in parallel (different adapter files)
- T013 and T014 can run in parallel (different files)
- Phase 3, 4, 5 can all start after Phase 2 completes (independent additions)

---

## Implementation Strategy

### MVP First (User Stories 1-3)

1. Complete Phase 1: Adapter updates (T002-T004)
2. Complete Phase 2: Core Codex integration with config (T005-T008)
3. Complete Phase 3: Graceful skip handling (T009-T010)
4. Complete Phase 4: Recursion guard verification (T011)
5. **VALIDATE**: Run deep review with and without Codex installed

### Full Delivery

6. Complete Phase 5: Fix loop re-review (T012)
7. Complete Phase 6: Ship flags and docs (T013-T014)
8. **FINAL VALIDATION**: Full ship pipeline with `--codex` flag

---

## Notes

- All changes to the deep-review command are in a single file: `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`
- The adapter command-map changes are small token additions to JSON files
- The ship pipeline flag changes follow the exact pattern of existing `--coderabbit`/`--no-coderabbit` flags
- Total: 13 tasks across 6 phases (T001 folded into T005)
