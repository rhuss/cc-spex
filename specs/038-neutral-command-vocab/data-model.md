# Data Model: Neutral Command Vocabulary

## Entities

### Command File

A markdown file in `spex/extensions/<ext>/commands/` that contains behavioral instructions for the AI agent.

| Attribute | Type | Description |
|-----------|------|-------------|
| path | string | Relative path from repo root (e.g., `spex/extensions/spex/commands/speckit.spex.ship.md`) |
| extension | string | Owning extension ID (e.g., `spex`, `spex-gates`) |
| has_capability_markers | boolean | Whether the file contains `<!-- harness:X -->` blocks |
| is_neutral | boolean | Whether the file uses only harness-neutral vocabulary |

**Lifecycle**: Source (neutral) -> Installed (neutral, via `specify extension add`) -> Adapted (harness-specific, via `spex-adapt-commands.sh`)

### Capability Marker

An HTML comment pair in a command file that delimits a section requiring harness-specific adaptation.

| Attribute | Type | Description |
|-----------|------|-------------|
| name | string | Capability identifier (e.g., `interactive-choice`, `subagent-dispatch`) |
| content | string | Neutral description of the desired behavior (default for unmapped harnesses) |
| open_tag | string | `<!-- harness:{name} -->` |
| close_tag | string | `<!-- /harness:{name} -->` |

**Canonical capabilities**:

| Name | Behavior | CC Tool |
|------|----------|---------|
| `interactive-choice` | Present user with structured options and get selection | AskUserQuestion |
| `subagent-dispatch` | Spawn a worker agent with a prompt and optional config | Agent tool |
| `parallel-dispatch` | Dispatch multiple worker agents concurrently | Multiple Agent tool calls in one response |
| `agent-teams` | Configure and use parallel agent teams with env/settings | Agent Teams, CLAUDE_CODE_EXPERIMENTAL, team_name |
| `worktree-isolation` | Create/manage isolated git worktrees for feature work | EnterWorktree, ExitWorktree, isolation: "worktree" |
| `harness-settings` | Read/write harness-specific configuration files | settings.json, settings.local.json |

### Mapping Table

A JSON file (`command-map.json`) in `spex/scripts/adapters/<harness>/` that defines transformations for one harness.

| Attribute | Type | Description |
|-----------|------|-------------|
| harness | string | Harness identifier (e.g., `claude`, `codex`, `opencode`) |
| version | string | Schema version for forward compatibility |
| inline | array | List of `{neutral, adapted}` text substitution pairs |
| sections | object | Map of capability-name to replacement content string |
| fallback_note | string | Template for unmapped capabilities. Placeholders: `{harness}`, `{fallback_text}` |

**Relationships**: One Mapping Table per harness. Mapping Table sections map to Capability Marker names.

### Adaptation Script

The shell script `spex/scripts/spex-adapt-commands.sh` that performs the transformation.

| Attribute | Type | Description |
|-----------|------|-------------|
| inputs | (harness, commands_dir, adapters_dir) | Runtime arguments |
| flags | --dry-run | Preview mode (FR-010) |
| output | transformed files or diff | Files in place or stdout diff |

## Relationships

```
Command File 1---* Capability Marker (a file may contain zero or more markers)
Mapping Table 1---* Inline Substitution (one table has many inline rules)
Mapping Table 1---* Section Replacement (one table maps many capabilities)
Capability Marker *---1 Section Replacement (each marker name maps to at most one replacement per harness)
Adaptation Script *---1 Mapping Table (script loads one table per run, selected by harness)
Adaptation Script 1---* Command File (script processes all command files in the extensions directory)
```

## Validation Rules

- Capability marker names must match `[a-z][a-z0-9-]*` (lowercase kebab-case)
- Mapping table `version` must be a semver string (e.g., `1.0.0`)
- Inline substitution pairs must be non-empty strings
- Section replacement values must be non-empty strings
- No capability marker may be nested inside another
- Open/close tags must be balanced within a file
