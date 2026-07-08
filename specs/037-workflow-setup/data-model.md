# Data Model: Workflow-Based Setup

## Entities

### Setup Workflow (setup.yml)
A spec-kit workflow YAML file that orchestrates spex installation and configuration.

| Attribute | Description |
|-----------|-------------|
| inputs | User-configurable parameters: integration, extensions, permissions |
| steps | Ordered list of workflow steps (shell, switch, if, init, prompt) |
| source | GitHub release URL or local file path |

### Bundle Manifest (bundle.yml)
A spec-kit bundle declaration for provenance and metadata tracking.

| Attribute | Description |
|-----------|-------------|
| id | Bundle identifier ("spex") |
| version | Semantic version (starts at 6.0.0) |
| provides.extensions | List of extension IDs and versions included |
| provides.workflows | List of workflow IDs and versions included |

### Integration Profile
A per-harness configuration set applied by the workflow's `switch` step.

| Harness | Permission File | Hook File | Context File | Adapter Scripts |
|---------|----------------|-----------|--------------|-----------------|
| Claude Code | `.claude/settings.json` | (built-in hooks) | `CLAUDE.md` | `hooks/context-hook.py`, `hooks/pretool-gate.py` |
| Codex | (N/A) | `.codex/hooks.json` | `AGENTS.md` | `adapters/codex/context-hook.py`, `adapters/codex/pretool-gate.py` |
| OpenCode | (N/A) | (N/A) | `AGENTS.md` | `adapters/opencode/spex-plugin.ts` |
| Default | (none) | (none) | (none) | (none) |

### Permission Profile
Agent-specific auto-approval rules configured by the workflow.

| Level | Claude Code | Codex | OpenCode |
|-------|------------|-------|----------|
| standard | Allowlist: `Skill`, `Bash(specify *)`, spex scripts | Hook-based: spex command validation | Plugin-based: spex command routing |
| yolo | `bypassPermissions` + broad allowlists | (same as standard, Codex has no bypass mode) | (same as standard) |
| none | No changes to settings | No hook configuration | No plugin configuration |

## Extension Dependency Graph

```
spex (core, always installed first)
├── spex-gates (depends on: spex)
│   ├── spex-deep-review (depends on: spex-gates)
│   └── spex-teams (depends on: spex-gates)
│   └── spex-collab (depends on: spex-gates)
├── spex-worktrees (depends on: spex)
└── spex-detach (depends on: spex)
```

**Installation order** (enforced by sequential workflow steps):
1. spex
2. spex-gates
3. spex-worktrees
4. spex-deep-review
5. spex-teams
6. spex-collab
7. spex-detach
