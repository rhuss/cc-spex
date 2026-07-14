# Data Model: Codex Hook Contract Migration

## JSON Schemas

### UserPromptSubmit Stdin (Codex v0.144+)

```json
{
  "prompt": "string (user's input text)",
  "turn_id": "string (session/turn identifier)",
  "cwd": "string (working directory path)",
  "permission_mode": "string (default|acceptEdits|plan|dontAsk|bypassPermissions)",
  "transcript_path": "string (path to conversation transcript)"
}
```

**Mapping from old contract:**

| Old field | New field | Notes |
|-----------|-----------|-------|
| `session_id` | `turn_id` | Used for marker file naming |
| `cwd` | `cwd` | Unchanged |
| `model` | (removed) | Not present in new contract |
| `permission_mode` | `permission_mode` | Same name, ignored by shared scripts |
| `prompt` | `prompt` | Unchanged |
| (new) | `transcript_path` | New field, ignored initially |

### PreToolUse Stdin (Codex v0.144+)

```json
{
  "tool_name": "string (name of the tool being called)",
  "tool_input": "object (arguments to the tool)",
  "turn_id": "string (session/turn identifier)",
  "cwd": "string (working directory path)",
  "permission_mode": "string (current permission mode)"
}
```

**Mapping from old contract:**

| Old field | New field | Notes |
|-----------|-----------|-------|
| `session_id` | `turn_id` | Used for marker file naming |
| `cwd` | `cwd` | Unchanged |
| `tool_name` | `tool_name` | Unchanged |
| `tool_input` | `tool_input` | Unchanged |
| (new) | `permission_mode` | New field, ignored by shared scripts |

### Context Injection Response

```json
{
  "systemMessage": "string (context text injected into the model's system prompt)"
}
```

### Deny Response (PreToolUse only)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "string (human-readable reason for denial)"
  }
}
```

### Allow Response

Empty stdout with exit code 0. No JSON needed.

## Marker Files

Unchanged from current implementation:

| File pattern | Purpose | Lifecycle |
|-------------|---------|-----------|
| `$TMPDIR/.claude-spex-skill-pending-<turn_id>` | Skill gate enforcement | Created on `/spex:` command, cleared on Skill tool call |

## hooks.json Structure (v0.144+)

```json
{
  "hooks": {
    "<EventName>": [
      {
        "matcher": "optional-regex (omitted = match all)",
        "hooks": [
          {
            "type": "command",
            "command": "sh /path/to/python-resolve.sh /path/to/script.py",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```
