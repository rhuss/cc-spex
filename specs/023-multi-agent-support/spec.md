# Feature Specification: Multi-Agent Harness Support

**Feature Branch**: `023-multi-agent-support`
**Created**: 2026-06-08
**Status**: Draft
**Input**: Brainstorm 16 - Multi-Agent Harness Support

## User Scenarios & Testing

### User Story 1 - Codex CLI User Runs spex Workflow (Priority: P1)

A developer using Codex CLI initializes spex in their project and runs the full SDD workflow (specify, plan, tasks, implement, review). The enforcement hooks prevent skipping stages, the model receives agent-appropriate instructions, and interactive prompts fall back to inline numbered lists since Codex lacks the AskUserQuestion tool.

**Why this priority**: Codex has the closest hook API to Claude Code (both UserPromptSubmit and PreToolUse), making it the lowest-risk target to prove the adapter architecture works.

**Independent Test**: Install spex with `--ai codex`, run `/speckit-specify` followed by `/speckit-plan`, verify that pretool gate blocks non-Skill tools until skill is loaded, verify AGENTS.md contains Codex-specific prompt guidance.

**Acceptance Scenarios**:

1. **Given** a project with spex initialized for Codex (`specify init --ai codex`), **When** the developer invokes a speckit command, **Then** the Codex-format hook scripts fire and enforce skill-first loading.
2. **Given** a Codex session with an active ship pipeline, **When** the developer tries to skip a stage, **Then** the pretool gate denies the tool call with the same enforcement as Claude Code.
3. **Given** a skill that uses AskUserQuestion on Claude Code, **When** running on Codex, **Then** the model presents options as a numbered inline list and waits for user input.

---

### User Story 2 - OpenCode User Runs spex Workflow (Priority: P2)

A developer using OpenCode initializes spex and runs the SDD workflow. The tool.execute.before plugin enforces skill-first loading and stage ordering. The `question` tool handles interactive prompts natively. Prompt interception logic (command validation, context injection) is embedded in skill preambles since OpenCode lacks UserPromptSubmit.

**Why this priority**: OpenCode has the largest community demand and validates the adapter pattern against a fundamentally different hook API (TypeScript plugin events vs Python hook scripts).

**Independent Test**: Install spex with `--ai opencode`, invoke `/speckit-specify`, verify the TypeScript plugin blocks non-Skill tools, verify the `question` tool is used for interactive prompts, verify skill preambles perform command validation.

**Acceptance Scenarios**:

1. **Given** a project with spex initialized for OpenCode, **When** the developer invokes a speckit command, **Then** the OpenCode TypeScript plugin fires tool.execute.before and enforces skill-first loading.
2. **Given** an OpenCode session, **When** a skill needs user input, **Then** it uses the `question` tool (not AskUserQuestion).
3. **Given** an OpenCode session without prompt interception hooks, **When** a skill loads, **Then** the skill preamble validates the command and injects context that would normally come from context-hook.py.

---

### User Story 3 - Extension Author Makes Extension Multi-Agent (Priority: P3)

An extension author (or the spex team maintaining built-in extensions) updates an extension's hooks and skills to work across all supported agents. The adapter framework provides clear patterns for mapping hook logic, interactive prompts, and subagent dispatch to each agent's capabilities.

**Why this priority**: Extension portability is the long-term multiplier. Without it, every extension is Claude Code-only, limiting the ecosystem.

**Independent Test**: Take the spex-gates extension, run its review-spec command on both Claude Code and OpenCode, verify both produce the same review output and enforce the same gates.

**Acceptance Scenarios**:

1. **Given** the spex-gates extension with adapter-aware hooks, **When** installed on a Codex project, **Then** the gate hooks fire via Codex's PreToolUse and enforce the same stage ordering as Claude Code.
2. **Given** the spex-teams extension, **When** running on OpenCode, **Then** parallel task dispatch uses OpenCode's Task tool instead of Claude Code's Agent tool.
3. **Given** the spex-deep-review extension, **When** running on Codex, **Then** review subagents are dispatched via Codex's subagent mechanism and produce the same review report format.

---

### User Story 4 - Agent-Optimized Instruction Files (Priority: P2)

When spex is initialized for a specific agent, the generated instruction file (CLAUDE.md or AGENTS.md) contains agent-specific guidance for skill invocation, interactive prompts, enforcement awareness, and team coordination. The model receives instructions tuned to its agent's actual capabilities.

**Why this priority**: The instruction file is the model's primary behavioral guide. Generic instructions cause hallucinated tool calls (e.g., calling AskUserQuestion on Codex) and missed capabilities (e.g., not using OpenCode's question tool).

**Independent Test**: Initialize spex for each agent, read the generated instruction file, verify it references the correct tools and patterns for that agent.

**Acceptance Scenarios**:

1. **Given** spex initialized for Codex, **When** the AGENTS.md is generated, **Then** it instructs the model to present interactive choices as numbered inline lists, not to call AskUserQuestion.
2. **Given** spex initialized for OpenCode, **When** the AGENTS.md is generated, **Then** it instructs the model to use the `question` tool for interactive prompts and notes that tool gates enforce blocking but prompt interception is advisory.
3. **Given** spex initialized for Claude Code, **When** CLAUDE.md is generated, **Then** it references AskUserQuestion, Agent tool, and /clear as usual (no regression).

---

### Edge Cases

- What happens when a project has multiple agent directories (both `.claude/` and `.opencode/`)? The adapter framework should detect the active agent at runtime and use the correct hooks.
- What happens when an OpenCode plugin fails to load? The skill preamble validation should still catch command misuse, degrading gracefully from plugin+skill enforcement to skill-only enforcement.
- What happens when Codex's hook JSON contract changes between versions? Hook adapters should validate input format and fail with a clear error rather than silently misbehaving.
- What happens when a skill references AskUserQuestion but runs on an agent without it? The model should follow the instruction file guidance and fall back to inline prompts, not hallucinate the tool.

## Clarifications

### Session 2026-06-08

- Q: What is the exact agent detection priority order for FR-008? → A: (1) Agent-specific env vars (CLAUDE_PROJECT_DIR, CODEX_SESSION_ID), (2) directory presence (.claude/, .codex/, .opencode/), (3) --ai value from .specify/init-options.json.
- Q: What language should the shared enforcement logic use? → A: Shell functions (POSIX-compatible) as the lowest common denominator. Claude Code/Codex adapters invoke from Python hooks. OpenCode adapter invokes from TypeScript plugin via child_process.exec.
- Q: What specific degradation applies per extension on limited agents? → A: spex-teams degrades to sequential execution (no parallel). spex-worktrees degrades to manual git worktree commands. spex-deep-review degrades to single-agent review. spex-gates and spex-collab work fully on all agents.

## Requirements

### Functional Requirements

- **FR-001**: System MUST provide hook adapter scripts for each supported agent (Claude Code, Codex, OpenCode) that map to the agent's native hook API.
- **FR-002**: The pretool gate logic (skill-first enforcement, stage ordering, teams enforcement, verify-before-commit) MUST be functionally equivalent across all adapters.
- **FR-003**: The context-hook logic (command validation, context injection) MUST be implemented as hook scripts for agents with UserPromptSubmit (Claude Code, Codex) and as skill preambles for agents without it (OpenCode).
- **FR-004**: System MUST generate agent-specific instruction files (CLAUDE.md or AGENTS.md) with correct tool references, enforcement expectations, and interactive prompt patterns for each agent.
- **FR-005**: Instruction files MUST include AskUserQuestion discrimination: the correct tool or fallback pattern for the target agent.
- **FR-006**: All spex extensions MUST work on all supported agents. Degradation behavior: spex-gates enforces the same stage ordering and tool gating on all agents (via hook adapters or skill preambles) and produces the same gate pass/fail output. spex-collab generates the same REVIEWERS.md format and phase-split proposals on all agents, with interactive prompts adapted to each agent's prompt mechanism. spex-teams degrades to sequential execution on agents without background tasks. spex-worktrees degrades to manual git worktree commands. spex-deep-review degrades to single-agent review on agents without subagent support.
- **FR-007**: The spex-teams extension MUST map parallel task dispatch to each agent's subagent mechanism (Agent tool for Claude Code, Task for OpenCode, subagents for Codex).
- **FR-008**: System MUST detect the active agent at runtime using this priority order: (1) agent-specific environment variables (CLAUDE_PROJECT_DIR, CODEX_SESSION_ID), (2) agent directory presence (.claude/, .codex/, .opencode/), (3) --ai value from .specify/init-options.json.
- **FR-009**: The `spex:init` command MUST install the correct hook adapter files for the detected or specified agent.
- **FR-010**: System MUST provide a local draft of an upstream spec-kit issue proposing a hook adapter framework for the spec-kit extension system.

### Key Entities

- **Hook Adapter**: A set of scripts/plugins that translate spex's enforcement logic to a specific agent's hook API. One adapter per supported agent.
- **Agent Instruction File**: The CLAUDE.md or AGENTS.md file generated during init, containing agent-specific behavioral guidance for the model.
- **Enforcement Logic Module**: The shared business logic for tool gating, stage enforcement, and command validation, consumed by all hook adapters.
- **Agent Capability Profile**: A declaration of what each agent supports (hooks, interactive prompts, background tasks, worktrees), used by the adapter framework to determine behavior.

## Success Criteria

### Measurable Outcomes

- **SC-001**: A developer can run the full SDD workflow (specify through verify) on Codex CLI with the same stage enforcement as Claude Code.
- **SC-002**: A developer can run the full SDD workflow on OpenCode with tool-gate enforcement and skill-preamble validation covering these enforcement scenarios: (a) skill-first loading blocks non-Skill tools, (b) stage ordering prevents skipping pipeline stages, (c) verify-before-commit blocks commit without verification, (d) command validation rejects malformed speckit commands, (e) context injection provides spec/plan/task paths to skills.
- **SC-003**: All 5 spex extensions (gates, teams, deep-review, collab, worktrees) produce correct output on both Codex and OpenCode.
- **SC-004**: Generated AGENTS.md files for each agent contain zero references to tools that don't exist on that agent (no AskUserQuestion on Codex, no Agent tool on OpenCode).
- **SC-005**: The hook adapter for Codex can be added by creating adapter scripts in a single directory without modifying any existing Claude Code hook code.
- **SC-006**: The upstream spec-kit issue draft is reviewed and ready to post.

## Out of Scope

- **Gemini CLI**: Explicitly deferred due to the ongoing Antigravity transition. No adapter is built for Gemini in this feature.
- **Other AI agents** (Aider, Cursor, Windsurf, etc.): Not targeted in this feature. The adapter architecture should not preclude future support, but no adapters are designed or tested for these agents.
- **Upstream spec-kit changes**: FR-010 produces a draft issue only. No upstream PRs or spec-kit core modifications are in scope.

## Error Handling

- **Adapter script execution failure**: If a hook adapter script fails (non-zero exit, missing interpreter, syntax error), the hook MUST log a clear error message identifying the adapter and failure reason, then fail open (allow the tool call) to avoid blocking the developer entirely. The error message MUST include the agent name and script path.
- **Unsupported agent detection**: If `spex:init` is invoked with `--ai <agent>` for an agent that has no adapter, the command MUST exit with a clear error listing the supported agents. If runtime detection (FR-008) cannot identify any known agent, the system MUST fall back to Claude Code behavior and log a warning.
- **Shared enforcement logic errors**: If the POSIX shell enforcement functions fail (e.g., `jq` not installed, malformed JSON state), the function MUST return a non-zero exit code with a diagnostic message. Adapter scripts MUST propagate this error to the hook response.
- **Missing agent directory during init**: If the target agent's config directory (e.g., `.codex/`) does not exist during init, the init command MUST create it. If creation fails (permissions), MUST exit with an actionable error.
- **Plugin load failure (OpenCode)**: If the OpenCode TypeScript plugin fails to load or register, the system degrades to skill-preamble-only enforcement. A warning MUST be logged on first skill invocation indicating reduced enforcement.

## Assumptions

- Codex CLI's UserPromptSubmit and PreToolUse hooks accept the same JSON stdin contract documented in OpenAI's Codex hooks documentation (to be verified with actual Codex install).
- OpenCode's `tool.execute.before` plugin event can deny tool calls by throwing an Error (documented behavior), but context injection via this event needs verification.
- OpenCode's `question` tool supports simple option lists. Multi-select with grouped headers may need simplification.
- The shared enforcement logic is written as POSIX-compatible shell functions. Claude Code/Codex adapters invoke from Python hooks. OpenCode adapter invokes from TypeScript plugin via child_process.exec.
- Existing Claude Code functionality has zero regressions from this change.
