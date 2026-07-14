# Research: Codex Hook Contract Migration

## Codex v0.144+ Hook Contract

### Decision
Use the documented v0.144+ contract from [learn.chatgpt.com/docs/hooks](https://learn.chatgpt.com/docs/hooks) as the authoritative reference.

### Rationale
The official docs match the observed behavior (hooks.json parse error with old format confirms the contract changed). Community guides corroborate the format.

### Key Findings

**UserPromptSubmit stdin fields:**
- `prompt` (string): user's input text
- `turn_id` (string): identifier for the turn/session
- `cwd` (string): working directory
- `permission_mode` (string): one of `default`, `acceptEdits`, `plan`, `dontAsk`, `bypassPermissions`
- `transcript_path` (string): path to conversation transcript

**UserPromptSubmit stdout:**
- Context injection: `{"systemMessage": "<text>"}`
- Block prompt: `{"decision": "block"}` or exit code 2
- Allow: exit 0 with no output
- Plain text stdout treated as `additionalContext`

**PreToolUse stdin fields:**
- `tool_name` (string): name of the tool being called
- `tool_input` (object): arguments to the tool
- `turn_id` (string): identifier for the turn/session
- `cwd` (string): working directory
- `permission_mode` (string): current permission mode

**PreToolUse stdout:**
- Deny: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "<reason>"}}`
- Allow: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow"}}` or exit 0 with no output
- Context: `{"systemMessage": "<text>"}`

**hooks.json format (v0.144+):**
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {"type": "command", "command": "...", "timeout": 600}
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "optional-regex",
        "hooks": [
          {"type": "command", "command": "...", "timeout": 600}
        ]
      }
    ]
  }
}
```

## Session Identifier: turn_id vs session_id

### Decision
Use `turn_id` as the session identifier. Fall back to `"unknown"` if absent.

### Rationale
Claude Code uses `session_id` which persists for the entire session. Codex's `turn_id` may be per-turn or per-session. The shared scripts use it only for marker file naming (`$TMPDIR/.claude-spex-skill-pending-<id>`). If `turn_id` is per-turn, markers would not persist, but the skill gate enforcement would still function within a single turn (which is the common case for `/spex:` commands).

### Alternatives Considered
- Extract session ID from `transcript_path` (e.g., hash the path): more robust but adds complexity
- Use a fixed identifier: would break multi-session isolation

## Output Format Mapping

### Old format → New format

| Purpose | Old (spex adapters) | New (Codex v0.144+) |
|---------|--------------------|--------------------|
| Context injection | `{"action": "context", "message": "..."}` | `{"systemMessage": "..."}` |
| Deny tool call | `{"action": "deny", "message": "..."}` | `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "..."}}` |
| Allow | exit 0, no output | exit 0, no output (unchanged) |
| Error in UserPromptSubmit | `{"action": "context", "message": "..."}` | `{"systemMessage": "..."}` |
