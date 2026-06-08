# Brainstorm: Multi-Agent Harness Support

**Date:** 2026-06-08
**Status:** active

## Problem Framing

cc-spex is built exclusively for Claude Code. Every hook, command, and packaging convention assumes Claude Code's plugin model. Meanwhile, spec-kit upstream already supports 32 agent integrations and can generate commands for OpenCode, Codex CLI, Gemini CLI, and dozens more. The speckit layer (specify, plan, tasks, implement) is already agent-portable. The gap is the spex layer: the enforcement hooks, interactive prompts, quality gates, and workflow discipline that make spex worth using.

The question: can we make spex's enforcement model portable across agent harnesses without maintaining separate codebases per agent, and without losing the mechanical enforcement that distinguishes spex from a spec template generator?

This supersedes brainstorm 15 (OpenCode-only adaptation) with a broader multi-agent scope.

## Research Findings

### Spec-kit's multi-agent architecture

Spec-kit uses an integration-based architecture with three base classes:
- **MarkdownIntegration** (most agents)
- **TomlIntegration** (Gemini, Tabnine)
- **SkillsIntegration** (Claude, Codex, Kimi)

`CommandRegistrar.register_commands_for_all_agents()` auto-detects installed agents and generates commands in the right format/location. Extensions auto-register for all detected agents without modification. Each agent has its own directory convention (`.claude/skills/`, `.opencode/command/`, `.agents/skills/`, `.gemini/skills/`).

### Agent capability matrix

| Capability | Claude Code | OpenCode | Codex CLI | Gemini CLI |
|---|---|---|---|---|
| Prompt interception | UserPromptSubmit | tui.prompt.append (different) | UserPromptSubmit | BeforeAgent |
| Pre-tool gate | PreToolUse | tool.execute.before | PreToolUse | BeforeTool |
| AskUser tool | AskUserQuestion | question | None | None |
| Skill discovery | .claude/skills/ | .opencode/ + .claude/ + .agents/ | AGENTS.md only | .gemini/skills/ |
| Background agents | Native | Community plugins | codex cloud exec | Antigravity (future) |
| Hook events | ~6 | ~25+ | 10 | 12 |
| Cross-compat | Reference | Reads .claude/ paths | AGENTS.md convention | CLAUDE_PROJECT_DIR alias |

### What spex depends on that is Claude Code-specific

| Component | What it does | Claude Code dependency |
|---|---|---|
| context-hook.py (UserPromptSubmit) | Command validation, context injection, skill-first enforcement | Claude Code hook API |
| pretool-gate.py (PreToolUse) | Tool gating, stage enforcement, teams enforcement, verify-before-commit | Claude Code hook API |
| AskUserQuestion (66 call sites) | Interactive multi-choice prompts | Claude Code tool |
| Agent Teams (spex-teams) | Parallel implementation with worktree isolation | Claude Code Agent tool |
| Status line | Flow/ship progress display | Claude Code statusLine.command |
| /clear, /loop | Context clearing, timed polling | Claude Code slash commands |

## Approaches Considered

### A: Dual-agent abstraction layer

Build an abstraction that detects the running agent and dispatches to the right implementation. Hook scripts would have equivalents per agent. Command files generated for all agent paths.

- Pros: Single codebase, correct behavior everywhere
- Cons: Every feature needs N implementations, testing multiplies, the abstraction itself becomes maintenance burden

### B: Working workflow, relaxed enforcement

Accept that some agents can't enforce at the hook level. Move enforcement into skill instructions (advisory). The SDD workflow works everywhere, enforcement is best-effort.

- Pros: Simpler, works within each agent's actual capabilities
- Cons: Process discipline degrades, model can skip stages, spex value proposition weakens

### C: Portable core, agent-specific enforcement (chosen)

Design a portable enforcement abstraction that adapts to each agent's capabilities. Full enforcement on agents with matching hook APIs (Claude Code, Codex), strong enforcement via tool gating on others (OpenCode), deferred for unstable platforms (Gemini/Antigravity).

- Pros: Each agent gets the strongest enforcement its platform supports, clean architecture, no enforcement degradation on capable agents
- Cons: Per-agent adapter code, need to track agent API changes

## Decision

**Approach C: Portable core with agent-specific enforcement adapters.**

The key insight is that the two hooks serve different purposes, and they have different portability profiles:

1. **Tool gating (pretool-gate.py)**: All agents have a pre-tool hook equivalent. This ports cleanly everywhere.
2. **Prompt interception (context-hook.py)**: Only Claude Code and Codex have UserPromptSubmit. For other agents, this logic moves into skill preambles. The tool gate covers the critical case (blocking non-Skill tools until a command is resolved), so the prompt interception gap is small.

### Priority ordering

1. **Codex CLI** first: Nearly identical hook API (UserPromptSubmit + PreToolUse), lowest effort to prove the architecture
2. **OpenCode** second: Largest community demand, proves the adapter pattern works with a different hook API
3. **Gemini CLI** deferred: Wait for Antigravity transition to stabilize

### Enforcement quality per agent

| Agent | Tool gating | Prompt interception | AskUser | Teams | Net |
|---|---|---|---|---|---|
| Claude Code | Full (PreToolUse) | Full (UserPromptSubmit) | AskUserQuestion | Agent tool | 100% |
| Codex CLI | Full (PreToolUse) | Full (UserPromptSubmit) | Inline text fallback | Subagents | ~90% |
| OpenCode | Full (tool.execute.before) | In-skill (no hook) | question tool | Community plugins | ~90% |
| Gemini CLI | Deferred | Deferred | Deferred | Deferred | Future |

## Key Requirements

### 1. Agent adapter framework

Each agent gets an adapter directory under `spex/hooks/`:

```
spex/hooks/
  claude/      # Existing Python hooks (context-hook.py, pretool-gate.py)
  codex/       # Same logic, Codex hook contract (JSON stdin/stdout)
  opencode/    # TypeScript plugin using tool.execute.before
  gemini/      # Deferred (shell scripts using BeforeTool/BeforeAgent)
```

The `spex:init` flow installs the right adapter for the detected agent. Enforcement logic stays centralized (shared functions/modules), only the hook contract differs.

### 2. AskUserQuestion wrapper pattern

Skills use a consistent pattern. The agent's instruction file (CLAUDE.md / AGENTS.md) teaches the model the correct mechanism:

- **Claude Code**: Use `AskUserQuestion` tool with header, options, multiSelect
- **OpenCode**: Use `question` tool with header and options
- **Codex CLI**: Present options as a numbered list in text output, wait for response. Do not attempt to call AskUserQuestion.
- **Gemini CLI**: Present options as a numbered list in text output, wait for response.

### 3. Agent-optimized instruction files

Each agent's instruction file (CLAUDE.md vs AGENTS.md) should be tailored to the agent's capabilities, not just reformatted. Key agent-specific sections:

| Aspect | Claude Code | Codex CLI | OpenCode |
|---|---|---|---|
| Skill invocation | "Use Skill tool" | "Use skill tool" | "Use skill tool" |
| Hook awareness | "Hooks enforce mechanically" | "Hooks enforce mechanically" | "Tool gates enforce, skill preambles validate" |
| Interactive prompts | "Use AskUserQuestion" | "Present numbered options inline" | "Use question tool" |
| Teams/parallel | "Use Agent tool with team_name" | "Use subagents when requested" | "Use Task for parallel work" |
| Context clearing | "Use /clear between phases" | "Start new session between phases" | "Start new session between phases" |

### 4. Extension portability (all extensions)

Extensions already register commands for all agents via spec-kit. The remaining work:

- **spex-gates**: Gate hooks use the adapter layer. Gate logic unchanged.
- **spex-teams**: Agent tool mapping (Claude Agent -> OpenCode Task -> Codex subagents). Worktree isolation becomes manual on agents without native support.
- **spex-deep-review**: Subagent dispatch adapts per agent. Review logic unchanged.
- **spex-collab**: Mostly markdown-based, ports with minimal changes.
- **spex-worktrees**: Manual worktree instructions where no native tool exists.

### 5. Upstream spec-kit proposal

Draft an issue proposing a hook adapter framework in spec-kit itself:
- Extensions declare hooks in extension.yml (already supported)
- Spec-kit generates agent-specific hook scripts during install
- Shared hook logic, per-agent hook contracts

This is a longer-term proposal. For now, adapters live in cc-spex.

## Open Questions

- What is the exact stdin/stdout JSON contract for Codex's UserPromptSubmit and PreToolUse? Need to test with an actual Codex CLI install.
- OpenCode's `tool.execute.before` can deny tool calls by throwing, but can it add context? Need to verify.
- Should the adapter framework detect the agent at init-time (static) or runtime (dynamic)? Static is simpler but doesn't handle projects used with multiple agents.
- How does the `question` tool in OpenCode handle multi-select? Does it support grouped options with headers?
- For the AGENTS.md AskUserQuestion discrimination: should skills reference the generic pattern ("ask the user") or the agent-specific tool name? Generic is more portable but less precise.
