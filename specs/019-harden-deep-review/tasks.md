# Tasks: Harden Deep Review Process

**Feature**: 019-harden-deep-review
**Generated**: 2026-05-22
**Spec**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)

## Phase 1: Setup

- [x] T001 Add `test_command` and `test_timeout_seconds` keys to `spex/extensions/spex-deep-review/config-template.yml` with defaults `""` and `300`

## Phase 2: Foundational

- [x] T002 Add test command auto-detection logic to Step 2 (Detect External Tools) in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: config override check, then Makefile, go.mod, package.json, pyproject.toml/setup.py detection order
- [x] T003 Add review hints detection to Step 2 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: check if `.specify/review-hints.md` exists and is non-empty

## Phase 3: User Story 1 - Fix Loop Test Execution (P1)

**Goal**: The fix loop runs the project's test suite after each fix round. Test failures become Critical findings.

**Independent Test**: Run deep review on a project with tests. Verify fix loop output includes test suite execution and test failures appear as findings.

- [x] T004 [US1] Add Step 7.6 (test suite execution) between current steps 5 and 6 in the fix loop in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: run detected test command with timeout, parse exit code
- [x] T005 [US1] Add test failure to findings conversion logic in Step 7.6 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: convert failures to Critical findings with `source_agent = "test-suite"`, `category = "regression"`, `confidence = 95`. When the test command exits non-zero but produces no parseable output, treat it as a single Critical finding with the exit code and any available stderr
- [x] T006 [US1] Add "no test command detected" skip-with-warning path in Step 7.6 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`
- [x] T007 [US1] Add test timeout handling in Step 7.6 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: read `test_timeout_seconds` from config, treat timeout as test failure
- [x] T008 [US1] Add "Test Suite (regression)" row to the gate outcome summary table in Step 9 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`
- [x] T009 [US1] Add test suite results section to the `review-findings.md` template in Step 8 in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`
- [x] T010 [US1] Add `[Test suite... passed/N failures]` progress reporting line in the Reference: Progress Reporting section in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

## Phase 4: User Story 2 - Spec-Anchored Test Validation (P2)

**Goal**: The test-quality agent cross-references spec acceptance scenarios against test verification methods.

**Independent Test**: Provide a spec with "confirm via kubectl get" and a test that checks in-memory. Verify the agent flags the mismatch.

- [x] T011 [P] [US2] Add spec-anchored validation checklist items to Agent 5 (Test Quality) prompt in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: for each acceptance scenario, find the test, check verification method match, flag mismatches
- [x] T012 [P] [US2] Add implicit verification method handling to the spec-anchored validation section: when scenario doesn't specify a method, verify test exists but don't flag mismatch. When a scenario references external systems not available in the test environment, note the scenario exists but mark verification method match as informational (not a finding)

## Phase 5: User Story 3 - Swallowed Error Detection (P3)

**Goal**: The correctness agent flags functions that log-but-don't-return errors from fallible operations.

**Independent Test**: Submit code with a function that logs an API error without returning it. Verify the correctness agent flags it.

- [x] T013 [P] [US3] Add swallowed error detection checklist items to Agent 1 (Correctness) prompt in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: general pattern plus Go, Python, JavaScript, Bash variants
- [x] T014 [P] [US3] Add intentional swallow handling to the correctness agent prompt: documented/commented swallows produce Minor findings with reduced confidence (50-60)

## Phase 6: User Story 4 - Review Hints Injection (P4)

**Goal**: `.specify/review-hints.md` content is injected into every review agent's preamble.

**Independent Test**: Create a review-hints.md file and run deep review. Verify hints content appears in agent prompts.

- [x] T015 [P] [US4] Add item 10 (PROJECT REVIEW HINTS) to the Common Preamble in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: conditional injection of `.specify/review-hints.md` content wrapped in clear delimiters
- [x] T016 [P] [US4] Add review hints injection instructions to Step 3 (Dispatch Review Agents) in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`: read hints file if detected, append to each agent's prompt

## Phase 7: Polish & Documentation

- [x] T017 Update `spex/docs/help.md` deep review section to mention test suite execution, review hints, and enhanced agent checks
- [x] T018 Add config key documentation (`test_command`, `test_timeout_seconds`) to the Prerequisites section in `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md`

## Dependencies

```
T001 (config) ← T002 (detection) ← T004-T010 (US1: fix loop tests)
T003 (hints detection) ← T015-T016 (US4: hints injection)
T011-T012 (US2: spec-anchored) — independent of US1
T013-T014 (US3: swallowed errors) — independent of US1
T015-T016 (US4: review hints) — independent of US1
T017-T018 (docs) — after all user stories
```

## Parallel Execution

Tasks marked [P] can be executed in parallel:
- T011+T012 (US2) can run in parallel with T013+T014 (US3) and T015+T016 (US4)
- US2, US3, US4 modify different agent prompt sections in the same file

## Implementation Strategy

**MVP**: Phase 1-3 (US1: fix loop test execution). This is the highest-impact intervention and independently testable.

**Incremental delivery**: Each user story phase produces independently testable value. US2-US4 can be delivered in any order after US1.

**Total tasks**: 18
- Setup: 1
- Foundational: 2
- US1 (fix loop tests): 7
- US2 (spec-anchored): 2
- US3 (swallowed errors): 2
- US4 (review hints): 2
- Polish: 2
