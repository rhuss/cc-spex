# Data Model: Unified Harness Marker Syntax

## Mapping Table (command-map.json)

Version 2.0.0 schema. One file per harness at `spex/scripts/adapters/<harness>/command-map.json`.

| Field | Type | Description |
|-------|------|-------------|
| `harness` | string | Harness identifier (e.g., "claude", "codex", "opencode") |
| `version` | string | Schema version, must be "2.0.0" |
| `tokens` | object | Key-value map of token replacements. Keys are kebab-case `[a-z][a-z0-9-]*`. Values are replacement strings (may contain `\n` for multi-line block content). |
| `fallback_note` | string | Template for unmapped tokens. Supports `{harness}` and `{fallback_text}` placeholders. |

**Migration from v1.0.0**: The `inline` array and `sections` object are merged into the single `tokens` object. Former inline entries use their neutral phrase's semantic intent as the key. Former section entries keep their existing marker name as the key.

## Inline Token

A placeholder within flowing text in a command markdown file.

| Attribute | Value |
|-----------|-------|
| Syntax | `{harness:key}` |
| Key format | `[a-z][a-z0-9-]*` |
| Replacement source | `tokens[key]` from mapping table |
| Fallback | `fallback_note` template if key not in tokens |
| After adaptation | Marker stripped, only replacement text remains |

## Block Marker

A pair of delimiters wrapping multi-line content in a command markdown file.

| Attribute | Value |
|-----------|-------|
| Opening syntax | `{harness:key}` (on its own line) |
| Closing syntax | `{/harness:key}` (on its own line) |
| Key format | `[a-z][a-z0-9-]*` |
| Content between markers | Neutral default text (replaced entirely) |
| Replacement source | `tokens[key]` from mapping table |
| Fallback | `fallback_note` template if key not in tokens |
| After adaptation | Opening marker, content, and closing marker all stripped; only replacement text remains |

## Token Registry (19 keys)

| Key | Type | Used In |
|-----|------|---------|
| `suppress-prompts-stamp` | inline | stamp |
| `suppress-prompts-verify` | inline | verify |
| `interactive-choice` | inline | ship, verify |
| `interactive-choice-skip` | inline | ship |
| `interactive-choice-must` | inline | ship |
| `spawn-worker` | inline | ship |
| `spawn-fresh-worker` | inline | ship |
| `general-worker` | inline | deep-review |
| `dispatch-review-agents` | inline | deep-review |
| `subagent-mechanism` | inline | deep-review |
| `use-subagent` | inline | deep-review |
| `teams-enabled` | inline | teams.implement, teams.orchestrate, teams.research |
| `teams-spawn` | inline | teams.orchestrate |
| `teams-research-spawn` | inline | teams.research |
| `parallel-dispatch` | block | deep-review |
| `agent-teams` | block | teams.orchestrate, teams.research |
| `agent-teams-dispatch` | block | teams.orchestrate |
| `agent-teams-research-dispatch` | block | teams.research |
| `worktree-isolation` | block | worktrees.manage |
