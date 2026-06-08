# Research: Multi-Agent Harness Support

## Agent Hook Contracts

### Claude Code

**UserPromptSubmit**: Hook receives JSON on stdin with `session_id`, `user_prompt`. Returns JSON with `hookSpecificOutput.additionalContext` (string) to inject context, or empty to pass through. Python scripts in `.claude/settings.json` hooks array.

**PreToolUse**: Hook receives JSON on stdin with `session_id`, `tool_name`, `tool_input`, `cwd`. Returns JSON with `hookSpecificOutput.permissionDecision` ("deny"/"allow") and `permissionDecisionReason`, or `additionalContext` for non-blocking reminders. Python scripts.

- Decision: Use as reference implementation. No changes needed.
- Rationale: Existing hooks work correctly. Adapters for other agents mirror this behavior.

### Codex CLI

**UserPromptSubmit**: Fires when user submits a prompt. Hook receives JSON on stdin with `session_id`, `cwd`, `model`, `permission_mode`. Returns JSON on stdout. Only `type: "command"` handlers work (not `prompt` or `agent` types). Configured in `.codex/hooks.json` or `config.toml`.

**PreToolUse**: Fires before tool execution. Same stdin contract. Can deny (block), rewrite input, or add context. Filter by `tool_name`. Exit code matters.

- Decision: Create Python adapter scripts mirroring Claude Code's hooks. Same language, different JSON field names where needed.
- Rationale: Codex's hook model is nearly identical to Claude Code's. Python is already a dependency for Claude Code hooks. Minimizes adapter complexity.
- Alternatives considered: Shell-only adapters (rejected: harder to parse JSON robustly in POSIX shell).

### OpenCode

**tool.execute.before**: TypeScript plugin event. Receives tool name and arguments. Can throw Error to deny, modify args, or pass through. No stdin/stdout JSON, it's a TypeScript function callback. Configured via `.opencode/plugins/` directory or npm package reference.

**No UserPromptSubmit equivalent**: The `tui.prompt.append` event injects text into the TUI prompt but does not intercept before the model sees it. Cannot validate commands or inject context pre-model.

- Decision: TypeScript plugin for tool gating. Skill preamble snippets for context injection.
- Rationale: Plugin API is the only enforcement mechanism. Skill preambles provide the context injection that hooks can't.
- Alternatives considered: Shell-based enforcement via custom OpenCode command (rejected: commands don't fire automatically, user must invoke them).

## Shared Logic Extraction

### Current State

`pretool-gate.py` (391 lines) contains 4 gates with enforcement logic tightly coupled to Claude Code's JSON response format. `context-hook.py` (185 lines) contains command validation and context injection.

### Extraction Strategy

Extract the decision logic (should this tool call be denied? what context should be injected?) from the response formatting (how to tell Claude Code the decision).

| Function | Input | Output | Used by |
|----------|-------|--------|---------|
| `skill-gate.sh` | tool_name, session_id | "deny:reason" or "allow" | All adapters |
| `stage-gate.sh` | tool_name, skill_name, state_file | "deny:reason" or "context:text" or "allow" | All adapters |
| `teams-gate.sh` | tool_name, tool_input_json, cwd | "deny:reason" or "allow" | All adapters |
| `verify-gate.sh` | tool_name, command, session_id, cwd | "context:text" or "allow" | All adapters |

Each shell function reads state files, evaluates conditions, and returns a simple string. The adapter wraps the result in agent-specific response format.

- Decision: POSIX shell functions with simple string return protocol.
- Rationale: Shell is the lowest common denominator. All adapters can call shell. Python can call via subprocess, TypeScript via child_process.exec.
- Alternatives considered: JSON output from shared functions (rejected: adds parsing overhead for simple allow/deny decisions).

## AskUserQuestion Mapping

### Current Usage Analysis

66 call sites across spex skills. Patterns:

| Pattern | Count | Example |
|---------|-------|---------|
| Binary choice (yes/no, proceed/skip) | ~30 | "Fix all / Let me pick / Skip" |
| Multi-option selection (3-4 choices) | ~25 | "Merge / Create PR / Keep branch" |
| Multi-select (checkboxes) | ~8 | Extension enable/disable |
| Single input with header | ~3 | Init questionnaire |

### Mapping Per Agent

| Agent | Tool | Multi-select | Headers | Structured options |
|-------|------|-------------|---------|-------------------|
| Claude Code | AskUserQuestion | Yes | Yes | Yes (label, description) |
| OpenCode | question | Needs testing | Yes | Yes (simpler) |
| Codex CLI | None (inline text) | No | No | Numbered list in text |
| Gemini CLI | None (inline text) | No | No | Numbered list in text |

- Decision: Skills use a descriptive pattern ("present options to user") and the AGENTS.md teaches the model the correct tool. No abstraction layer in skill code.
- Rationale: Adding a runtime tool-detection wrapper in each skill adds complexity. The instruction file approach is simpler and equally effective since the model reads AGENTS.md before any skill.
- Alternatives considered: Runtime wrapper function (rejected: skills are markdown, not executable code; the model interprets instructions, so instruction-level mapping is the natural approach).

## Agent Instruction File Differences

### Key Sections Per Agent

| Section | Claude Code | Codex | OpenCode |
|---------|------------|-------|----------|
| Interactive prompts | "Use AskUserQuestion tool" | "Present numbered list, wait for response" | "Use question tool" |
| Enforcement model | "Hooks enforce mechanically" | "Hooks enforce mechanically" | "Tool gates enforce. Skill preambles validate commands." |
| Context clearing | "Use /clear between phases" | "Start new session" | "Start new session" |
| Parallel work | "Use Agent tool with team_name" | "Use subagents when explicitly requested" | "Use Task tool for parallel dispatch" |
| Background tasks | "Use run_in_background" | "Not available" | "Community plugin territory" |
| Worktrees | "Use EnterWorktree" | "Use git worktree add manually" | "Use git worktree add manually" |

- Decision: Three separate template files, not conditional logic in one template.
- Rationale: Each template is ~50-100 lines. Conditionals would make a single template harder to read than three simple files.
