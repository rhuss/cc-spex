# Tasks: Multi-Agent Harness Support

**Input**: Design documents from `specs/023-multi-agent-support/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1=Codex, US2=OpenCode, US3=Extensions, US4=Instruction files)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: Create directory structure for adapters and shared logic

- [x] T001 Create adapter directories: `spex/scripts/adapters/codex/`, `spex/scripts/adapters/opencode/`, `spex/scripts/hooks/shared/`
- [x] T002 [P] Create instruction template directory: `spex/templates/agents-md/`
- [x] T003 [P] Create skill preamble directory: `spex/templates/skill-preamble/`

---

## Phase 2: Foundational (Shared Logic Extraction + Agent Detection)

**Purpose**: Extract enforcement logic from existing Claude Code hooks into reusable shell functions, and implement agent detection. BLOCKS all adapter work.

**Note**: This phase refactors existing hooks. Claude Code behavior MUST remain identical after extraction (zero regression).

- [x] T004 Extract skill-gate logic from `spex/scripts/hooks/pretool-gate.py` (lines 85-110) into `spex/scripts/hooks/shared/skill-gate.sh`. Shell function takes tool_name and session_id, returns "deny:reason" or "allow". Reads marker file from $TMPDIR.
- [x] T005 Extract stage-gate logic from `spex/scripts/hooks/pretool-gate.py` (lines 165-273) into `spex/scripts/hooks/shared/stage-gate.sh`. Shell function takes tool_name, skill_name, state_file_path, returns "deny:reason" or "context:text" or "allow". Reads .spex-state.
- [x] T006 [P] Extract teams-gate logic from `spex/scripts/hooks/pretool-gate.py` (lines 117-158) into `spex/scripts/hooks/shared/teams-gate.sh`. Shell function takes tool_name, tool_input_json, cwd, returns "deny:reason" or "allow". Reads extension registry and phase file.
- [x] T007 [P] Extract verify-gate logic from `spex/scripts/hooks/pretool-gate.py` (lines 280-327) into `spex/scripts/hooks/shared/verify-gate.sh`. Shell function takes tool_name, command, session_id, cwd, returns "context:text" or "allow". Reads .spex-state and marker files.
- [x] T008 Refactor `spex/scripts/hooks/pretool-gate.py` to call shared shell functions via subprocess instead of inline logic. Verify Claude Code behavior is identical (run `make release` to confirm).
- [x] T008b Extract context-hook logic from `spex/scripts/hooks/context-hook.py` into `spex/scripts/hooks/shared/context-hook.sh`. Shell function takes user_prompt, session_id, cwd, returns "inject:context_json" or "skip". Handles command validation (known command list check) and skill-pending marker creation.
- [x] T008c Refactor `spex/scripts/hooks/context-hook.py` to call shared `context-hook.sh` via subprocess. Verify Claude Code behavior is identical.
- [x] T009 Create `spex/scripts/hooks/shared/detect-agent.sh`. Shell function with no arguments, returns agent key string ("claude", "codex", "opencode"). Priority: (1) env vars CLAUDE_PROJECT_DIR/CODEX_SESSION_ID, (2) directory presence .claude/.codex/.opencode/, (3) --ai from .specify/init-options.json.

**Checkpoint**: Existing Claude Code hooks refactored to use shared logic. `make release` passes. Agent detection works.

---

## Phase 3: User Story 1 - Codex CLI Support (Priority: P1) MVP

**Goal**: A developer using Codex CLI can run the full SDD workflow with the same enforcement as Claude Code.

**Independent Test**: Initialize spex with `specify init --ai codex`, verify hook scripts are installed in `.codex/`, verify pretool gate blocks non-Skill tools, verify stage ordering enforcement during ship pipeline.

### Implementation for User Story 1

- [x] T010 [US1] Create `spex/scripts/adapters/codex/pretool-gate.py`. Read JSON from stdin per Codex hook contract (session_id, cwd, tool_name, tool_input). Call shared shell functions (skill-gate.sh, stage-gate.sh, teams-gate.sh, verify-gate.sh). Format deny/allow/context responses per Codex expected output.
- [x] T011 [US1] Create `spex/scripts/adapters/codex/context-hook.py`. Read JSON from stdin per Codex UserPromptSubmit contract. Validate /speckit-* commands against known command list. Write skill-pending marker file. Inject spex context as additional context. Format response per Codex expected output.
- [x] T012 [US1] Update `spex/scripts/spex-init.sh` to detect agent via detect-agent.sh and install Codex adapter hooks to `.codex/hooks.json` when agent is "codex". Preserve existing Claude Code install path.

**Checkpoint**: Codex CLI enforces skill-first loading and stage ordering via its hooks.

---

## Phase 4: User Story 4 - Agent-Optimized Instruction Files (Priority: P2)

**Goal**: Each agent gets a tailored instruction file with correct tool names, enforcement expectations, and AskUserQuestion fallback patterns.

**Independent Test**: Run `spex:init` for each agent, read generated CLAUDE.md/AGENTS.md, verify zero references to tools that don't exist on that agent.

### Implementation for User Story 4

- [x] T013 [P] [US4] Create `spex/templates/agents-md/claude.md` template. AskUserQuestion instructions, Agent tool for teams, /clear for context, hooks enforce mechanically. Extract from current CLAUDE.md generation logic in spex-init.sh.
- [x] T014 [P] [US4] Create `spex/templates/agents-md/codex.md` template. Inline numbered list for interactive prompts (no AskUserQuestion), subagents for parallel work, new session for context clearing, hooks enforce mechanically.
- [x] T015 [P] [US4] Create `spex/templates/agents-md/opencode.md` template. `question` tool for interactive prompts, Task tool for parallel work, new session for context clearing, tool gates enforce + skill preambles validate.
- [x] T016 [US4] Update `spex/scripts/spex-init.sh` to select and install the correct instruction template based on detected agent. Claude gets CLAUDE.md, Codex and OpenCode get AGENTS.md from their respective templates.

**Checkpoint**: Each agent gets correct instruction file. No hallucinated tool references.

---

## Phase 5: User Story 2 - OpenCode Support (Priority: P2)

**Goal**: A developer using OpenCode can run the SDD workflow with tool-gate enforcement and skill-preamble validation.

**Independent Test**: Initialize spex with `specify init --ai opencode`, verify TypeScript plugin blocks non-Skill tools, verify `question` tool is used for prompts, verify skill preambles perform command validation.

### Implementation for User Story 2

- [x] T017 [US2] Create `spex/scripts/adapters/opencode/spex-plugin.ts`. TypeScript OpenCode plugin subscribing to `tool.execute.before`. Call shared shell functions via `child_process.execSync`. Throw Error to deny, return to allow. Handle skill-gate, stage-gate, teams-gate, verify-gate.
- [x] T018 [US2] Create `spex/templates/skill-preamble/opencode-preamble.md`. Markdown snippet that OpenCode skills include at the top. Performs command validation (checks skill name against known list), injects spex context (plugin root, session state), replaces what context-hook.py does on Claude Code.
- [x] T019 [US2] Update `spex/scripts/spex-init.sh` to install OpenCode adapter: copy plugin to `.opencode/plugins/`, install skill preamble, generate AGENTS.md from opencode template.

**Checkpoint**: OpenCode enforces tool gating via plugin. Skills self-validate via preamble.

---

## Phase 6: User Story 3 - Extension Portability (Priority: P3)

**Goal**: All 5 spex extensions work across Claude Code, Codex, and OpenCode with defined degradation behavior.

**Independent Test**: Run review-spec on both Claude Code and OpenCode, verify same review output. Run spex-teams on OpenCode, verify sequential fallback.

### Implementation for User Story 3

- [x] T020 [P] [US3] Update `spex/extensions/spex-gates/` command files: replace hard-coded AskUserQuestion references with agent-neutral prompt pattern ("present options to the user using the agent's interactive prompt mechanism"). Gate logic and review output unchanged.
- [x] T021 [P] [US3] Update `spex/extensions/spex-teams/` command files: add agent-specific subagent dispatch. Claude Code uses Agent tool, OpenCode uses Task tool, Codex uses subagents. Add sequential execution fallback when no parallel mechanism available.
- [x] T022 [P] [US3] Update `spex/extensions/spex-deep-review/` command files: add single-agent review fallback for agents without subagent support. Review logic and report format unchanged.
- [x] T023 [P] [US3] Update `spex/extensions/spex-worktrees/` command files: add manual git worktree instructions for agents without native EnterWorktree. Claude Code path unchanged.
- [x] T024 [P] [US3] Update `spex/extensions/spex-collab/` command files: replace AskUserQuestion references with agent-neutral prompt pattern. Verify REVIEWERS.md generation works without agent-specific tools.
- [x] T025 [US3] Update `spex/extensions/spex/commands/speckit.spex.using-superpowers.md`: add multi-agent awareness section documenting which tools are available per agent and the correct prompt pattern.

**Checkpoint**: All extensions produce correct output on Claude Code, Codex, and OpenCode.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, upstream proposal, and validation

- [x] T026 [P] Update `README.md`: add Multi-Agent Support section describing supported agents, enforcement quality per agent, and adapter architecture.
- [x] T027 [P] Update `spex/docs/help.md`: add multi-agent commands, adapter references, and agent-specific guidance.
- [x] T028 [P] Finalize `brainstorm/16-speckit-hook-adapter-proposal.md` as ready-to-post upstream issue.
- [x] T029 Run `make release` to validate schema, integration test, and confirm zero regressions on Claude Code.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies, can start immediately
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS all adapter work.
- **US1 Codex (Phase 3)**: Depends on Foundational (shared logic extraction)
- **US4 Instructions (Phase 4)**: Depends on Setup only. Can run in parallel with Phase 3.
- **US2 OpenCode (Phase 5)**: Depends on Foundational. Can run in parallel with Phase 3.
- **US3 Extensions (Phase 6)**: Depends on Phase 3 and Phase 5 (needs adapters to exist for testing)
- **Polish (Phase 7)**: Depends on all prior phases

### User Story Dependencies

- **US1 (Codex)**: Depends on Foundational only. Independent of US2, US3, US4.
- **US4 (Instructions)**: Depends on Setup only. Independent of adapters.
- **US2 (OpenCode)**: Depends on Foundational only. Independent of US1.
- **US3 (Extensions)**: Depends on US1 and US2 (needs adapters to test against).

### Parallel Opportunities

- T002, T003 can run in parallel with T001
- T004, T005, T006, T007 can run in parallel (different shared logic files)
- T010, T011 can run in parallel (different adapter files, same agent)
- T013, T014, T015 can run in parallel (different template files)
- T017 and T018 can run in parallel (plugin vs preamble)
- T020, T021, T022, T023, T024 can run in parallel (different extensions)
- T026, T027, T028 can run in parallel (different doc files)
- Phase 3 and Phase 4 can run in parallel (no dependencies between them)
- Phase 3 and Phase 5 can run in parallel (different agents, same shared logic)

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (shared logic + detect-agent)
3. Complete Phase 3: US1 Codex adapter
4. **STOP and VALIDATE**: Test Codex enforcement independently
5. This proves the adapter architecture works

### Incremental Delivery

1. Setup + Foundational -> Shared logic ready
2. Add Codex adapter -> Test enforcement -> MVP validated
3. Add instruction templates -> Test per-agent files
4. Add OpenCode adapter -> Test tool gating + preambles
5. Adapt extensions -> Test cross-agent operation
6. Polish docs + upstream proposal

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All shared shell functions use simple string return protocol: "deny:reason", "context:text", or "allow"
- Existing Claude Code hooks MUST not regress. T008 validates via `make release`.
- The OpenCode TypeScript plugin is the only non-shell/Python artifact in this feature
