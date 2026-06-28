# Tasks: Focused Interactive Smoke Test

**Input**: Design documents from `specs/029-smoke-test-rethink/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this feature modifies existing files in an established plugin codebase.

- [x] T001 Read the existing smoke test command at `spex/extensions/spex/commands/speckit.spex.smoke-test.md` to understand current structure and section organization
- [x] T002 Read the existing ship pipeline Stage 8 in `spex/extensions/spex/commands/speckit.spex.ship.md` (lines around "Stage 8: Smoke Test") to understand current integration

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The spec template change defines the `## Smoke Test` section format that all other tasks depend on.

**⚠️ CRITICAL**: The smoke test command and ship pipeline both reference this section format.

- [x] T003 [US3] Add optional `## Smoke Test` section to the spec template at `.specify/templates/spec-template.md` — insert between Success Criteria and Assumptions sections, include guidance comments explaining when to include it (runnable artifacts only), the numbered-list format, and a placeholder example with 3 sample scenarios

---

## Phase 3: User Story 1 + 2 — Core Smoke Test Command (Priority: P1) 🎯 MVP

**Goal**: Rewrite the smoke test command to parse scenarios from `## Smoke Test` section, automate setup/execution, and present each scenario for human judgment. Auto-skip when section is absent.

**Independent Test**: Invoke `/speckit-spex-smoke-test` against a spec with a `## Smoke Test` section and verify Claude automates setup and asks only for judgment. Invoke against a spec without the section and verify it skips.

### Implementation for User Story 1 + 2

- [x] T004 [US1] Rewrite `spex/extensions/spex/commands/speckit.spex.smoke-test.md` — replace the entire command with the new focused smoke test implementation. The new command must:
  - Keep the HARD-GATE no-simulation section unchanged
  - Keep the Ship Pipeline Guard section unchanged
  - Remove the "Context Freshness" tip (no subagent, so context freshness is the user's choice)
  - Rewrite Prerequisites/Spec Resolution to also check for `## Smoke Test` section presence
  - Replace Step 1 (Parse Acceptance Scenarios) with new parsing logic: scan for `## Smoke Test` heading, extract numbered list items as scenarios. If section absent, report skip and exit (FR-002). If section present but empty/malformed, warn and skip. If >5 scenarios, warn but proceed (FR-011)
  - Remove Step 2 (App Lifecycle) as a separate step — fold app startup into scenario execution (start on first scenario that needs it, keep running for subsequent scenarios)
  - Remove Step 3 (Subagent Phase 1) entirely — no subagent architecture (FR-007)
  - Replace Step 4 (Interactive Review Phase 2) with direct single-session execution: for each scenario, Claude reads the instruction, determines what setup is needed (start server, navigate browser, run command), performs the setup, collects evidence (output, screenshots), presents evidence to human, asks for pass/fail/skip verdict
  - Add failure handling: when verdict is "fail", offer to investigate cause, suggest fix, allow retry. Record both initial failure and retry result (FR-013)
  - Add Playwright MCP graceful degradation: attempt Playwright for browser scenarios, fall back to manual instructions if unavailable (FR-008)
  - Keep Step 5 (Write SMOKE-TEST.md) but simplify the report format per the plan: header with feature/date/spec/summary, then per-scenario blocks with instruction, evidence, verdict, notes
  - Keep Step 6 (Record Results) using existing `spex-ship-state.sh smoke-test-record`
  - Keep Step 7 (Cleanup) for app process shutdown
  - Keep the HARD-GATE mandatory results report section — update the report format to show scenario instructions instead of Given/When/Then

**Checkpoint**: At this point, the smoke test command works for specs with and without `## Smoke Test` sections.

---

## Phase 4: User Story 4 — Ship Pipeline Integration (Priority: P2)

**Goal**: Update the ship pipeline's Stage 8 to detect the `## Smoke Test` section instead of parsing acceptance scenarios.

**Independent Test**: Run the ship pipeline on a spec with and without `## Smoke Test` section and verify correct Stage 8 behavior.

### Implementation for User Story 4

- [x] T005 [US4] Update Stage 8 in `spex/extensions/spex/commands/speckit.spex.ship.md` — change the scenario detection from `grep -c '\*\*Given\*\*' "$SPEC_FILE"` to `grep -c '## Smoke Test' "$SPEC_FILE"`. Update the `HAS_SCENARIOS` variable name to `HAS_SMOKE_TEST` for clarity. Update the announcement text from "N acceptance scenarios found" to "Smoke test section found". Remove the two-phase subagent description from the announcement. Simplify the subagent prompt to invoke the new smoke test command without mentioning Phase 1/Phase 2 architecture. Update the "no scenarios" message from "No acceptance scenarios for smoke test" to "No smoke test section — skipping"

---

## Phase 5: User Story 5 — Persistent Report (Priority: P3)

**Goal**: SMOKE-TEST.md report captures evidence and verdicts for every run.

**Independent Test**: Run a smoke test to completion and verify SMOKE-TEST.md is created with correct structure.

- [x] T006 [US5] Verify SMOKE-TEST.md report generation is correctly implemented in T004 — no separate task needed since report writing is part of the core command rewrite. This task is a verification checkpoint: read the report format section in the rewritten command and confirm it matches the plan's report contract (header with feature/date/spec/summary, per-scenario blocks, retry documentation)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation updates and cross-reference maintenance.

- [x] T007 [P] Update `spex/docs/help.md` — update any smoke test references to reflect the new focused approach (curated scenarios from `## Smoke Test` section, no auto-verify, no subagent)
- [x] T008 [P] Update `README.md` — update smoke test description in the Commands Reference table and any workflow descriptions that mention the smoke test

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — read-only orientation
- **Foundational (Phase 2)**: T003 depends on T001/T002 (understanding current code)
- **US1+2 (Phase 3)**: T004 depends on T003 (template defines the format the command parses)
- **US4 (Phase 4)**: T005 depends on T004 (ship pipeline references the new command behavior)
- **US5 (Phase 5)**: T006 depends on T004 (verification of report generation in T004)
- **Polish (Phase 6)**: T007, T008 depend on T004 and T005 (docs reflect final implementation)

### User Story Dependencies

- **US1+2 (P1)**: Core command rewrite — blocks US4, US5
- **US3 (P2)**: Spec template — blocks US1+2 (defines the section format)
- **US4 (P2)**: Ship pipeline — depends on US1+2
- **US5 (P3)**: Report verification — depends on US1+2

### Within Each User Story

- T001/T002 are read-only orientation, can run in parallel
- T003 must complete before T004
- T004 must complete before T005, T006, T007, T008
- T007 and T008 can run in parallel

### Parallel Opportunities

- T001 and T002 can run in parallel (read-only)
- T007 and T008 can run in parallel (different files)

---

## Implementation Strategy

### MVP First (User Story 1+2 Only)

1. Complete Phase 1: Setup (read existing code)
2. Complete Phase 2: Foundational (spec template change)
3. Complete Phase 3: Core smoke test command rewrite
4. **STOP and VALIDATE**: Test with a spec that has `## Smoke Test` and one without
5. This delivers the full core value: focused interactive smoke test with auto-skip

### Incremental Delivery

1. T001-T002 → Understand existing code
2. T003 → Spec template has `## Smoke Test` section
3. T004 → Smoke test command works end-to-end (MVP!)
4. T005 → Ship pipeline uses new detection mechanism
5. T006 → Report format verified
6. T007-T008 → Documentation updated

---

## Notes

- T004 is the largest task — it's a full rewrite of a ~600-line skill file. It should be done in one pass to maintain consistency.
- No test tasks are included — this is a CLI plugin with manual verification via `make release`.
- The smoke test command is a markdown skill file, not executable code. "Implementation" means rewriting the skill instructions.
- US1 and US2 are combined because US2 (auto-skip) is the "else" branch of US1's detection logic — they share the same file and parsing code.
