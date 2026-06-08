# Data Model: Multi-Agent Harness Support

## Entities

### Agent Capability Profile

Declares what each supported agent provides. Used by detect-agent.sh and spex-init.sh to select adapters and generate instruction files.

| Field | Type | Description |
|-------|------|-------------|
| key | string | Agent identifier (matches spec-kit integration key) |
| env_var | string | Environment variable that confirms this agent is active |
| directory | string | Agent-specific directory in project root |
| has_prompt_hook | boolean | Whether UserPromptSubmit or equivalent exists |
| has_pretool_hook | boolean | Whether PreToolUse or equivalent exists |
| ask_user_tool | string or null | Tool name for interactive prompts (null = inline fallback) |
| subagent_tool | string or null | Tool for parallel task dispatch |
| instruction_file | string | Filename for agent instructions (CLAUDE.md or AGENTS.md) |
| hook_format | string | Hook script format: "python", "typescript", "shell" |

**Instances:**

| key | env_var | directory | prompt_hook | pretool_hook | ask_user | subagent | instruction | hook_format |
|-----|---------|-----------|-------------|-------------|----------|----------|-------------|-------------|
| claude | CLAUDE_PROJECT_DIR | .claude/ | yes | yes | AskUserQuestion | Agent | CLAUDE.md | python |
| codex | CODEX_SESSION_ID | .codex/ | yes | yes | null | subagent | AGENTS.md | python |
| opencode | OPENCODE_* | .opencode/ | no | yes | question | Task | AGENTS.md | typescript |

### Hook Adapter

A set of scripts that translate between shared enforcement logic and an agent's hook API.

| Field | Type | Description |
|-------|------|-------------|
| agent_key | string | References Agent Capability Profile |
| adapter_dir | string | Path under spex/scripts/adapters/{agent}/ |
| scripts | list[string] | Files in the adapter directory |
| install_target | string | Where hooks are installed in the project |

**Instances:**

| agent_key | adapter_dir | scripts | install_target |
|-----------|-------------|---------|----------------|
| claude | (none, uses existing hooks/) | context-hook.py, pretool-gate.py | .claude/settings.json hooks |
| codex | adapters/codex/ | context-hook.py, pretool-gate.py | .codex/hooks.json |
| opencode | adapters/opencode/ | spex-plugin.ts | .opencode/plugins/ |

### Shared Enforcement Function

A POSIX shell function that evaluates an enforcement rule and returns a simple result string.

| Field | Type | Description |
|-------|------|-------------|
| name | string | Function name (e.g., skill-gate.sh) |
| inputs | list[string] | Required arguments |
| output_protocol | string | "deny:reason", "context:text", or "allow" |
| state_files_read | list[string] | State files consulted during evaluation |

**Instances:**

| name | inputs | reads |
|------|--------|-------|
| skill-gate.sh | tool_name, session_id | $TMPDIR/.claude-spex-skill-pending-{session_id} |
| stage-gate.sh | tool_name, skill_name, state_file_path | .specify/.spex-state |
| teams-gate.sh | tool_name, tool_input_json, cwd | .specify/extensions/.registry, .specify/.spex-phase |
| verify-gate.sh | tool_name, command, session_id, cwd | .specify/.spex-state, $TMPDIR/.claude-spex-verified-{session_id} |
| detect-agent.sh | (none) | env vars, directory presence, .specify/init-options.json |

## Relationships

```
Agent Capability Profile 1──* Hook Adapter
Hook Adapter *──* Shared Enforcement Function
Agent Capability Profile 1──1 Instruction File Template
```

- Each agent has exactly one adapter (or reuses existing hooks for Claude Code).
- Each adapter invokes one or more shared enforcement functions.
- Each agent has one instruction file template.

## State Transitions

No new state machines. The existing `.spex-state` flow/ship state machine is unchanged. Adapters read it but don't modify the state model.

## File Artifacts Per Agent

When `spex:init` runs for a given agent:

| Artifact | Claude Code | Codex | OpenCode |
|----------|------------|-------|----------|
| Instruction file | CLAUDE.md (updated) | AGENTS.md (generated) | AGENTS.md (generated) |
| Hook config | .claude/settings.json | .codex/hooks.json | (plugin auto-discovered) |
| Hook scripts | hooks/context-hook.py, hooks/pretool-gate.py | adapters/codex/*.py | adapters/opencode/spex-plugin.ts |
| Shared logic | hooks/shared/*.sh | hooks/shared/*.sh | hooks/shared/*.sh |
| Skill preamble | (not needed) | (not needed) | templates/skill-preamble/opencode-preamble.md |
