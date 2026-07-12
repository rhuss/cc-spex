# Implementation Plan: Unified Harness Marker Syntax

**Branch**: `039-robust-harness-markers` | **Date**: 2026-07-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/039-robust-harness-markers/spec.md`

## Summary

Replace the fragile two-mechanism adaptation system (HTML-comment markers for sections + exact prose-matching for inline) with a unified `{harness:key}` token syntax. Update the adaptation script to process both inline tokens and block markers (`{harness:key}...{/harness:key}`) in a single pass. Migrate all 3 mapping tables from `"inline"` + `"sections"` to a single `"tokens"` object. Convert all 8 command files that use current markers (7 with inline phrases + 1 block-only). Add `--debug` flag and post-adaptation validation.

## Technical Context

**Language/Version**: Bash (POSIX-compatible), Python 3 (hooks), Markdown (commands)
**Primary Dependencies**: `jq`, `diff` (for --dry-run), `awk` (for text processing)
**Storage**: Filesystem (markdown command files, JSON mapping tables)
**Testing**: `make release` (schema validation + integration test), `--dry-run` comparison
**Target Platform**: macOS / Linux (any POSIX shell)
**Project Type**: CLI plugin (spec-kit extension bundle)
**Performance Goals**: adapt-commands step completes in < 5 seconds (SC-004)
**Constraints**: No upstream spec-kit changes. No compiled dependencies beyond `jq`.
**Scale/Scope**: 8 command files with markers (7 inline + 1 block-only), 3 mapping tables, 1 adaptation script

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | PASS | Following full SDD workflow |
| II. Extension Architecture | PASS | Commands stay in `spex/extensions/<ext>/commands/`. Script stays in `spex/scripts/`. |
| III. Extension Composability | PASS | No cross-extension dependencies introduced. adapt-commands operates uniformly. |
| IV. Quality Gates | PASS | Standard review gates apply. |
| V. Naming Discipline | PASS | No new commands or skills. Script name unchanged. |
| VI. Skill Autonomy | PASS | No skill logic changes. Only marker syntax in command files. |
| VII. State as Scripts | PASS | Adaptation is a script, not inline bash. |

No violations.

## Project Structure

### Documentation (this feature)

```text
specs/039-robust-harness-markers/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
spex/
├── scripts/
│   ├── spex-adapt-commands.sh              # MODIFY: unified marker processing
│   └── adapters/
│       ├── claude/command-map.json          # MODIFY: inline+sections → tokens
│       ├── codex/command-map.json           # MODIFY: inline+sections → tokens
│       └── opencode/command-map.json        # MODIFY: inline+sections → tokens
├── extensions/
│   ├── spex/commands/
│   │   └── speckit.spex.ship.md            # MODIFY: inline phrases → tokens
│   ├── spex-deep-review/commands/
│   │   └── speckit.spex-deep-review.run.md # MODIFY: HTML markers → block tokens + inline phrases → tokens
│   ├── spex-gates/commands/
│   │   ├── speckit.spex-gates.verify.md    # MODIFY: inline phrases → tokens
│   │   └── speckit.spex-gates.stamp.md     # MODIFY: inline phrases → tokens
│   ├── spex-teams/commands/
│   │   ├── speckit.spex-teams.implement.md # MODIFY: inline phrases → tokens
│   │   ├── speckit.spex-teams.orchestrate.md # MODIFY: HTML markers → block tokens + inline phrases → tokens
│   │   └── speckit.spex-teams.research.md  # MODIFY: HTML markers → block tokens + inline phrases → tokens
│   └── spex-worktrees/commands/
│       └── speckit.spex-worktrees.manage.md # MODIFY: HTML markers → block tokens
```

## Research Findings

### R1: Current Marker Inventory

**HTML-comment section markers** (6 total across 4 files):

| File | Marker | Lines |
|------|--------|-------|
| `deep-review.run.md` | `parallel-dispatch` | 175 |
| `teams.orchestrate.md` | `agent-teams` | 15 |
| `teams.orchestrate.md` | `agent-teams-dispatch` | 126 |
| `teams.research.md` | `agent-teams` | 15 |
| `teams.research.md` | `agent-teams-research-dispatch` | 138 |
| `worktrees.manage.md` | `worktree-isolation` | 415 |

**Inline substitution phrases** (15 entries, 7 files):

| File | Phrases | Count |
|------|---------|-------|
| `ship.md` | interactive prompt, worker agent, fresh-context worker, subagent mechanism | 5 |
| `deep-review.run.md` | dispatch review agents, subagent mechanism, general-purpose worker | 5 |
| `stamp.md` | suppress interactive prompts (stamp variant) | 1 |
| `verify.md` | suppress interactive prompts (verify variant), structured interactive prompt | 2 |
| `teams.implement.md` | parallel agent teams feature | 1 |
| `teams.orchestrate.md` | team mechanism to spawn teammates | 2 |
| `teams.research.md` | team mechanism to spawn research agents | 2 |

Note: `finish.md` and `submit.md` contain the substring "suppress all interactive prompts" but are NOT targets of the inline substitutions (the actual entries are longer, more specific phrases).

### R2: Token Key Design

Token keys derived from the existing inline phrases and section marker names:

**Inline tokens** (replacing prose-matching):

| Key | Neutral Phrase | Claude Replacement |
|-----|---------------|-------------------|
| `no-interactive-prompts` | do NOT present interactive prompts | do NOT use AskUserQuestion |
| `suppress-prompts-stamp` | suppress all interactive prompts, complete the stamp | suppress all user prompts (do NOT use AskUserQuestion), complete the stamp |
| `suppress-prompts-verify` | suppress all interactive prompts, complete the verification | suppress all user prompts (do NOT use AskUserQuestion), complete the verification |
| `interactive-choice` | present the choice using a structured interactive prompt | present the choice using `AskUserQuestion` |
| `interactive-choice-skip` | using a structured interactive prompt (skip in autonomous mode) | using AskUserQuestion (skip in autonomous mode) |
| `interactive-choice-must` | **This MUST be a structured interactive prompt...** | **This MUST be an AskUserQuestion tool call...** |
| `spawn-worker` | Spawn a worker agent with the following prompt | Spawn a subagent using the Agent tool with the following prompt |
| `spawn-fresh-worker` | spawn a fresh-context worker agent | spawn a fresh-context Agent (subagent_type: general-purpose) |
| `general-worker` | a general-purpose worker agent | `subagent_type: "general-purpose"` via the Agent tool |
| `dispatch-review-agents` | Dispatch all review agents using multiple subagent calls in a single message | Dispatch all 5 agents using multiple Agent tool calls in a single message |
| `subagent-mechanism` | the agent's subagent mechanism | the Agent tool |
| `use-subagent` | Use the agent's subagent mechanism with | Use the Agent tool with |
| `teams-enabled` | The parallel agent teams feature must be enabled | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS must be set |
| `teams-spawn` | Use the agent's team mechanism to spawn teammates | Use the **Agent** tool with `team_name` to spawn teammates in isolated worktrees |
| `teams-research-spawn` | Use the agent's team mechanism to spawn research agents | Use the **Agent** tool with `team_name` to spawn research agents. Each agent explores in its own context |

**Block tokens** (replacing HTML-comment sections, same keys as before):
- `parallel-dispatch`
- `agent-teams`
- `agent-teams-dispatch`
- `agent-teams-research-dispatch`
- `worktree-isolation`

Total: 20 token keys in the unified `tokens` object.

### R3: Script Architecture Decision

The adaptation script currently has two phases:
1. Phase 1: awk-based inline substitutions from TSV file
2. Phase 2: awk-based section marker replacement

The new unified approach:
1. Phase 1: Replace `{harness:key}...{/harness:key}` block markers (must run first to avoid partial matches where an inline token key matches inside a block)
2. Phase 2: Replace `{harness:key}` inline tokens
3. Phase 3: Post-adaptation validation (scan for leftover `{harness:` markers)

Block replacement must precede inline replacement because a block's opening `{harness:key}` would otherwise be treated as an inline token.

## Design

### Unified Mapping Table Schema (v2.0.0)

```json
{
  "harness": "claude",
  "version": "2.0.0",
  "tokens": {
    "no-interactive-prompts": "do NOT use AskUserQuestion",
    "agent-teams": "Enable Claude Code Agent Teams by setting...\n(multi-line block content)",
    "parallel-dispatch": "Dispatch all agents using multiple **Agent tool** calls..."
  },
  "fallback_note": "> **Note:** This capability is not available on {harness}. {fallback_text}"
}
```

Both inline tokens and block markers share the same `tokens` namespace. The script distinguishes them by syntax in the source file (`{harness:key}` alone = inline, `{harness:key}` on its own line followed by content and `{/harness:key}` = block).

### Script Processing Order

```
1. Load mapping table, extract tokens into key-value lookup
2. Create temp directory for atomic output
3. For each .md file:
   a. Phase 1: Find {harness:key}...{/harness:key} blocks, replace with tokens[key] or fallback
   b. Phase 2: Find remaining {harness:key} inline tokens, replace with tokens[key] or fallback
   c. If --debug: log each replacement to stderr
4. Phase 3: Scan all processed files for leftover {harness: markers, warn on stderr
5. If --dry-run: output diff and exit
6. Move transformed files into place
```

### Cross-Task Interfaces

**spex-adapt-commands.sh** (modified):
```
Interface: spex-adapt-commands.sh [--dry-run] [--debug] <harness> <commands-dir> <adapters-dir>
  --debug:    flag, outputs per-marker trace to stderr
  All other args: unchanged from current version
  Exit codes: 0 = success, 1 = unclosed block marker or malformed JSON
  Stderr:     --debug traces, post-adaptation warnings, progress messages
```

## Quickstart

### For implementers

1. Update `spex/scripts/spex-adapt-commands.sh` to handle `{harness:key}` tokens and `{harness:key}...{/harness:key}` blocks
2. Update `spex/scripts/adapters/claude/command-map.json` to v2.0.0 `tokens` format
3. Convert HTML-comment markers in 4 command files to `{harness:key}...{/harness:key}` blocks
4. Convert inline prose phrases in 7 command files to `{harness:key}` tokens
5. Update Codex and OpenCode mapping tables to v2.0.0
6. Verify: `./spex/scripts/spex-adapt-commands.sh --dry-run claude .specify/extensions spex/scripts/adapters`

### Verification checklist

- [ ] `grep '<!-- harness:' spex/extensions/*/commands/*.md` returns 0 matches
- [ ] `./spex/scripts/spex-adapt-commands.sh --dry-run claude ...` shows all tokens replaced
- [ ] `./spex/scripts/spex-adapt-commands.sh --dry-run codex ...` shows Codex replacements
- [ ] Running adaptation twice produces byte-identical output
- [ ] `make release` passes
