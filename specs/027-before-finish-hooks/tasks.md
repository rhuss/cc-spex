# Tasks: Before/After Finish Hook Support

**Input**: Design documents from `specs/027-before-finish-hooks/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)

## Phase 1: Setup

**Purpose**: No project initialization needed. All target files already exist.

(No setup tasks for this feature.)

## Phase 2: User Story 1 - before_finish Hook Support (P1)

**Story Goal**: When a user runs `/speckit-spex-finish`, registered `before_finish` hooks fire before Phase 1 verification. Optional hooks prompt the user; mandatory hooks auto-execute.

**Independent Test**: Run `/speckit-spex-finish` with a `before_finish` hook registered in extensions.yml and verify the prompt appears before verification.

- [ ] T001 [US1] Read the hook-reading boilerplate from the core spec-kit implement template. Reference: run `cat /Users/rhuss/.local/share/uv/tools/specify-cli/lib/python3.12/site-packages/specify_cli/core_pack/commands/implement.md` and extract the "Pre-Execution Checks" section (lines 16-48). This is the pattern to copy.
- [ ] T002 [US1] Add "## Pre-Execution Checks" section to `spex/extensions/spex/commands/speckit.spex.finish.md` BEFORE the existing "## Phase 1: Verification" section. The section must: (a) check if `.specify/extensions.yml` exists, (b) read `hooks.before_finish` entries, (c) filter out `enabled: false` hooks, (d) skip hooks with non-empty `condition` fields, (e) convert dot-notation command names to hyphen notation for slash commands, (f) for optional hooks output the prompt text, (g) for mandatory hooks auto-execute, (h) if extensions.yml missing or malformed skip silently. Add autonomous mode handling: when `.specify/.spex-state` exists with `ask` of `smart` or `never`, optional hooks execute without prompting.
- [ ] T003 [US1] Add `before_finish` hook registration to `spex/extensions/spex/extension.yml` under the `hooks:` section. Add: `before_finish:` with `command: speckit.spex.smoke-test`, `optional: true`, `prompt: "Run interactive smoke test before finishing?"`, `description: "Walk through spec acceptance scenarios interactively"`.

## Phase 3: User Story 2 - after_finish Hook Support (P2)

**Story Goal**: Registered `after_finish` hooks fire after the finish command completes its action, fixing the current dead-config gap.

**Independent Test**: Verify the existing `after_finish` flow-state hook fires after finish completes.

- [ ] T004 [US2] Add after_finish hook-reading logic to `spex/extensions/spex/commands/speckit.spex.finish.md` AFTER Phase 6 (State and Status Line Cleanup) and BEFORE Phase 7 (Watch Mode). Same pattern as T002 but reads `hooks.after_finish` entries. Only fires when watch mode is NOT active (`WATCH_MODE` is false or `ACTION_TAKEN` is not `"pr"`). When watch mode IS active, the after_finish hooks fire during the watch cleanup paths instead.

## Phase 4: User Story 3 - Next-Steps Text Updates (P3)

**Story Goal**: Review-code and deep-review next-steps output mentions smoke test as step 1.

**Independent Test**: Run review-code or deep-review and verify `/speckit-spex-smoke-test` appears in the next-steps output.

- [ ] T005 [P] [US3] Update the "Next Steps" section in `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md` (around line 416). Change the existing two-step list to three steps: (1) `/speckit-spex-smoke-test (walk through acceptance scenarios)`, (2) `/clear (free context for final gate)`, (3) `/speckit-spex-finish (verify + merge/PR, all-in-one)`.
- [ ] T006 [P] [US3] Update the "Next Steps" section in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` (around line 598). Same three-step list as T005.

## Phase 5: Polish & Documentation

**Purpose**: Documentation updates per constitution requirement.

- [ ] T007 [P] Update `README.md` to mention the `before_finish` hook for smoke test integration in the workflow description and the extension hooks section.
- [ ] T008 [P] Update `spex/docs/help.md` to mention `/speckit-spex-smoke-test` in the workflow quick reference and note that it fires automatically via hook before finish.

## Dependencies

```text
T001 → T002 (need reference pattern before copying it)
T002 → T003 (hook boilerplate must exist before registering hooks)
T002 → T004 (before_finish pattern informs after_finish pattern)
T005, T006 are independent of T001-T004 (different files)
T007, T008 are independent of all other tasks (different files)
```

## Parallel Execution

```text
Group 1: T001 (sequential, reference reading)
Group 2: T002 (sequential, depends on T001)
Group 3: T003 + T005 + T006 + T007 + T008 (all parallel, different files)
Group 4: T004 (sequential, depends on T002)
```

## Implementation Strategy

**MVP**: T001 + T002 + T003 (User Story 1 only). This delivers the core value: smoke test prompt before finish.

**Full delivery**: All 8 tasks. Small feature, can be completed in a single pass.

## Summary

- **Total tasks**: 8
- **US1 (before_finish hooks)**: 3 tasks
- **US2 (after_finish hooks)**: 1 task
- **US3 (next-steps text)**: 2 tasks
- **Polish/docs**: 2 tasks
- **Parallel opportunities**: T003, T005, T006, T007, T008 can all run in parallel after T002
