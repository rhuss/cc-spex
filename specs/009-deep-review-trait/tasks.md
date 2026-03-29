# Tasks: Deep-Review Trait

**Input**: Design documents from `/specs/009-deep-review-trait/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

**Tests**: No automated test suite (Markdown/Bash plugin). Verification via `make reinstall` + manual Claude Code session testing.

**Organization**: Tasks grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US5)
- All paths relative to repository root

---

## Phase 1: Setup

**Purpose**: Register the trait and create directory structure

- [x] T001 Register `deep-review` in VALID_TRAITS in `spex/scripts/spex-traits.sh`
- [x] T002 Create overlay directory structure `spex/overlays/deep-review/commands/`
- [x] T003 Create overlay file `spex/overlays/deep-review/commands/speckit.implement.append.md` with sentinel marker and skill delegation (< 30 lines per constitution)

**Checkpoint**: `spex-traits.sh init --enable "deep-review"` succeeds, overlay applied to `.claude/commands/speckit.implement.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core skill and review-code integration that ALL user stories depend on

**Warning**: No user story work can begin until this phase is complete

- [x] T004 Create deep-review skill directory `spex/skills/deep-review/`
- [x] T005 Create `spex/skills/deep-review/SKILL.md` with frontmatter (name, description) and orchestration skeleton: trait detection, stage routing, agent dispatch loop, findings merge, fix loop, and review-findings.md generation
- [x] T006 Add trait detection to `spex/skills/review-code/SKILL.md`: after spec compliance check, read `.specify/spex-traits.json`, if `deep-review` enabled invoke `{Skill: spex:deep-review}`
- [x] T007 Define the Finding output schema in deep-review SKILL.md: structured markdown format with FINDING-ID, Severity, Confidence, File, Lines, Category, Description, Rationale, Fix, and Self-Verification checklist (per research.md R5)
- [x] T008 Implement changed files detection logic in deep-review SKILL.md: git diff `<main-branch>...HEAD` union with uncommitted changes, with narrowed scope for re-review rounds (FR-013)
- [x] T009 Implement findings merge and deduplication algorithm in deep-review SKILL.md: file + overlapping line range + category matching, detail-preserving merge, source tracking (FR-031, research.md R4)
- [x] T010 Implement review-findings.md generation in deep-review SKILL.md: review metadata, per-round findings, summary with severity counts, gate outcome, overwrite semantics (FR-032)
- [x] T011 Implement gate behavior logic in deep-review SKILL.md: superpowers context (blocking) vs. manual context (advisory) per FR-044

**Checkpoint**: Deep-review skill file complete with all infrastructure. Review-code detects trait and delegates. Not yet functional (agent prompts needed in Phase 3).

---

## Phase 3: User Story 1 - Enhanced Review After Implementation (Priority: P1) MVP

**Goal**: Multi-perspective review with 5 agents and autonomous fix loop, triggered via superpowers quality gate

**Independent Test**: Enable `deep-review` trait, run `/speckit.implement` on a small feature with known issues, verify agents detect issues, fix loop runs, `review-findings.md` produced

### Implementation for User Story 1

- [x] T012 [P] [US1] Write Correctness Agent prompt template in deep-review SKILL.md: role/scope gate, mutation safety + shared references + logic errors + resource cleanup + error paths checklist, anti-sycophancy instructions, distrust instruction, confidence scoring, language-aware adaptation, structured output format (FR-020, FR-021, FR-080, FR-081)
- [x] T013 [P] [US1] Write Architecture & Idioms Agent prompt template in deep-review SKILL.md: role/scope gate, dead code + complexity + duplication + naming + comments checklist, anti-sycophancy, distrust, confidence scoring, language-aware adaptation, structured output format
- [x] T014 [P] [US1] Write Security Agent prompt template in deep-review SKILL.md: role/scope gate, input validation + injection + secrets + RBAC + CRD/CEL + auth checklist, anti-sycophancy, distrust, confidence scoring, language-aware adaptation, structured output format
- [x] T015 [P] [US1] Write Production Readiness Agent prompt template in deep-review SKILL.md: role/scope gate, goroutine leaks + unbounded channels + critical sections + memory patterns + operator patterns checklist, anti-sycophancy, distrust, confidence scoring, language-aware adaptation, structured output format
- [x] T016 [P] [US1] Write Test Quality Agent prompt template in deep-review SKILL.md: role/scope gate, coverage gaps + weak assertions + wrong-reason passes + missing edge cases + missing regression tests checklist, anti-sycophancy, distrust, confidence scoring, language-aware adaptation, structured output format
- [x] T017 [US1] Implement sequential agent dispatch in deep-review SKILL.md: iterate through 5 agents, dispatch each via Agent tool with isolated context (FR-022), parse structured output, collect findings, report per-agent progress (FR-090)
- [x] T018 [US1] Implement autonomous fix loop in deep-review SKILL.md: collect Critical + Important findings, apply fixes in reverse line order per file (FR-046), stage changes, re-dispatch agents on modified files only, max 3 rounds (FR-041), gate check after each round (FR-042, FR-043)
- [x] T019 [US1] Implement Stage 1 to Stage 2 transition in deep-review SKILL.md: check spec compliance score >= 95% before Stage 2, handle no-spec case (skip Stage 1), handle Stage 1 failure with user guidance (FR-010, FR-011, FR-012, FR-014)
- [x] T020 [US1] Implement progress reporting output in deep-review SKILL.md: Stage transitions, per-agent start/complete with finding count, fix round progress, gate outcome (FR-090)

**Checkpoint**: Full deep-review with 5 sequential agents, fix loop, and review-findings.md works end-to-end via superpowers quality gate. Validate with `make reinstall` + test session.

---

## Phase 4: User Story 2 - Manual Review with Hints (Priority: P2)

**Goal**: Users can run `/spex:review-code <hint text>` with focus hints injected into agent prompts

**Independent Test**: Run `/spex:review-code check CRD validation completeness`, verify hint text appears in each agent's context

### Implementation for User Story 2

- [x] T021 [US2] Add hint text passthrough in review-code SKILL.md: capture argument text from `/spex:review-code` invocation, pass to deep-review skill (FR-070)
- [x] T022 [US2] Implement hint injection in deep-review SKILL.md: when hint text is present, append it as "Additional Review Focus" section in each agent's prompt, supplementing (not replacing) standard checklist (FR-071)

**Checkpoint**: Manual `/spex:review-code focus on X` works with hint injection. Validate by checking agent prompts include hint text.

---

## Phase 5: User Story 3 - Parallel Review via Teams (Priority: P2)

**Goal**: When teams trait is also enabled, review agents run in parallel via Claude Code Agent Teams

**Independent Test**: Enable both `deep-review` and `teams`, run review, verify agents launch in parallel and findings merge correctly

### Implementation for User Story 3

- [x] T023 [US3] Add teams trait detection in deep-review SKILL.md: check `.specify/spex-traits.json` for `teams` enabled, branch to parallel vs. sequential dispatch
- [x] T024 [US3] Implement parallel agent dispatch in deep-review SKILL.md: dispatch all 5 agents via multiple Agent tool calls in a single message, each with isolated context, collect results as agents complete (FR-050)
- [x] T025 [US3] Implement parallel progress reporting in deep-review SKILL.md: report per-agent completion as each finishes even in parallel mode (FR-091)

**Checkpoint**: Parallel review with teams trait produces identical findings to sequential mode, completes faster. Validate with both traits enabled.

---

## Phase 6: User Story 4 - External Review Tool Integration (Priority: P3)

**Goal**: Include CodeRabbit CLI and GitHub Copilot CLI as optional external review perspectives alongside internal agents

**Independent Test**: Install one or both external CLIs, enable `deep-review`, run review, verify external findings merge with internal findings

### Implementation for User Story 4

- [x] T026 [P] [US4] Implement external tool detection in deep-review SKILL.md: check `which coderabbit` and `which copilot` availability, set flags for inclusion (FR-060, FR-062)
- [x] T027 [P] [US4] Implement CodeRabbit invocation and parser in deep-review SKILL.md: run `coderabbit review --prompt-only --type uncommitted --no-color`, split on `=============` delimiters, extract file/line/severity/description, map severity (critical->Critical, major->Important, minor->Minor), set category=external, source_agent=coderabbit, confidence=75 (FR-061, research.md R2)
- [x] T028 [P] [US4] Implement Copilot CLI invocation and parser in deep-review SKILL.md: run `copilot -s -p` with structured output prompt requesting findings in parseable format, extract severity/file/line/description, set category=external, source_agent=copilot, confidence=75 (FR-064, research.md R2)
- [x] T029 [US4] Add external tool error handling in deep-review SKILL.md: timeout and error graceful degradation for both tools, log failures in review-findings.md, proceed with internal agents and any working external tools (FR-024 pattern)
- [x] T036 [US4] Implement cross-tool deduplication in deep-review SKILL.md: when both CodeRabbit and Copilot find the same issue, deduplicate using standard FR-031 rules, noting both external sources (FR-065)

**Checkpoint**: External tool findings appear in merged results alongside internal agents. With both tools installed, both contribute. With neither installed, review works with internal agents only. Validate all three paths.

---

## Phase 7: User Story 5 - Review Without Superpowers (Priority: P3)

**Goal**: Deep-review works when only the `deep-review` trait is enabled (no superpowers dependency)

**Independent Test**: Enable only `deep-review` (not superpowers), run `/spex:review-code`, verify full multi-perspective review runs

### Implementation for User Story 5

- [x] T030 [US5] Verify review-code trait detection works for manual invocation path in review-code SKILL.md: ensure deep-review is invoked regardless of whether superpowers triggered the call (FR-003)
- [x] T031 [US5] Verify gate behavior defaults to advisory mode when invoked manually without superpowers context in deep-review SKILL.md (FR-044)

**Checkpoint**: Deep-review works identically whether triggered by superpowers gate or manual invocation. Only gate behavior differs (blocking vs. advisory).

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final validation and documentation

- [x] T032 [P] Update `spex/skills/help/SKILL.md` to include deep-review trait in help output
- [x] T033 [P] Update `spex/docs/` with deep-review trait documentation if help docs exist
- [ ] T034 Run `make reinstall` and validate end-to-end: enable trait, run implement on test feature, verify all 5 agents run, fix loop operates, review-findings.md generated
- [ ] T035 Validate trait composability: test with superpowers+deep-review, teams+deep-review, all three combined, and deep-review alone

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 completion, BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2, MVP target
- **US2 (Phase 4)**: Depends on Phase 2 (minimal integration with US1 dispatch logic)
- **US3 (Phase 5)**: Depends on Phase 2 (adds parallel path alongside US1's sequential path)
- **US4 (Phase 6)**: Depends on Phase 2 (adds external agent to dispatch pipeline)
- **US5 (Phase 7)**: Depends on Phase 2 (verification of existing paths, minimal new code)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: No dependencies on other stories. MVP.
- **US2 (P2)**: Can start after Phase 2. Adds hint parameter to existing dispatch logic.
- **US3 (P2)**: Can start after Phase 2. Adds parallel dispatch path alongside sequential.
- **US4 (P3)**: Can start after Phase 2. Adds CodeRabbit and Copilot as optional external tools.
- **US5 (P3)**: Can start after Phase 2. Verification of existing logic, minimal new code.

### Within Each User Story

- Agent prompt templates (T012-T016) can all run in parallel
- Dispatch logic (T017) depends on prompt templates
- Fix loop (T018) depends on dispatch logic
- Progress reporting (T020) can run alongside fix loop

### Parallel Opportunities

- T012-T016: All 5 agent prompt templates can be written in parallel
- T032-T033: Polish documentation tasks can run in parallel
- US2-US5 can all start after Phase 2 completion (independent of each other)

---

## Parallel Example: User Story 1

```
# Write all 5 agent prompts in parallel:
Task: "Write Correctness Agent prompt in deep-review SKILL.md"
Task: "Write Architecture Agent prompt in deep-review SKILL.md"
Task: "Write Security Agent prompt in deep-review SKILL.md"
Task: "Write Production Readiness Agent prompt in deep-review SKILL.md"
Task: "Write Test Quality Agent prompt in deep-review SKILL.md"

# Then sequentially:
Task: "Implement sequential agent dispatch"
Task: "Implement autonomous fix loop"
Task: "Implement stage transition logic"
Task: "Implement progress reporting"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004-T011)
3. Complete Phase 3: User Story 1 (T012-T020)
4. **STOP and VALIDATE**: `make reinstall`, enable deep-review, test with a small feature
5. If working: proceed to US2-US5

### Incremental Delivery

1. Setup + Foundational -> Trait registered, skill skeleton ready
2. Add US1 -> Full review with 5 agents + fix loop (MVP!)
3. Add US2 -> Manual hints support
4. Add US3 -> Parallel execution with teams
5. Add US4 -> CodeRabbit integration
6. Add US5 -> Independence verification
7. Polish -> Help docs, composability validation

---

## Notes

- All implementation lives in Markdown files (SKILL.md). No compiled code.
- The deep-review SKILL.md will be the largest file (~500-800 lines including all 5 agent prompts).
- Agent prompts are the most critical deliverable. Quality of prompts directly determines review quality.
- Fix loop mechanics are complex but contained within a single SKILL.md section.
- Testing is manual: `make reinstall` then run Claude Code session with trait enabled.
