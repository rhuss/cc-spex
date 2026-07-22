# Brainstorm: Leverage Spec-Kit 0.7.x Workflows and Integrations

**Date**: 2026-04-18
**Context**: Branch `016-traits-to-extensions` already created 5 extension bundles (spex, spex-gates, spex-teams, spex-worktrees, spex-deep-review) against spec-kit 0.5.2. Spec-kit has since jumped to 0.7.4 with major new features.

## Problem

The current 016 migration builds custom infrastructure that spec-kit 0.7.x now provides natively:

1. **Ship pipeline** (`speckit.spex.ship.md`, 788 lines): Custom state management, resume logic, stage sequencing. Spec-kit now has a declarative workflow engine with `run`, `resume`, `status`, gate steps.
2. **Agent detection in init** (`spex-init.sh`): Custom agent directory mapping. Spec-kit now has `specify integration install/switch/upgrade` with 28+ agents.
3. **Extension version requirements**: Manifests target `>=0.5.2`, but workflow features require `>=0.7.2`.

## Decisions

### Ship becomes a workflow YAML

Replace the `speckit.spex.ship` command with a `spex-ship` workflow definition.

- `specify workflow run spex-ship` replaces `/spex:ship`
- Gets resume, status, and step graph for free
- Oversight levels map to gate behavior:
  - `never` = auto-approve all gates
  - `smart` = auto-approve unambiguous, pause on ambiguous/blockers
  - `always` = pause at every gate
- Subagent forking for implement/review stages stays (isolation is our concern, not the workflow engine's)
- The ship command file becomes a thin wrapper that invokes `specify workflow run`

### Hooks and workflow gates compose, not compete

- **Hooks (spex-gates)**: Always-on quality discipline. Fires on every `speckit.specify`, `speckit.plan`, etc. regardless of context. This is the unconditional rigor.
- **Workflow gates**: Structured checkpoints with approve/reject/resume semantics. Used inside ship workflow.
- **Coordination**: When a workflow is running, hooks detect this and suppress to avoid double-reviewing. Outside workflows, hooks fire normally.

### Init simplification

Gut `spex-init.sh` to a thin wrapper:
- `specify integration install/upgrade` handles agent detection and directory mapping
- Extension installation from plugin directory (`specify extension add <path> --dev`)
- Plugin ecosystem detection (configurable)
- Version gating (`>=0.7.4`)
- Status line configuration
- `.gitignore` setup
- Remove ALL legacy migration code (beads, old commands, constitution symlink, traits config)

### Plugin ecosystem detection (configurable)

Init scans for companion plugins and records their availability. Extensions can conditionally invoke plugin capabilities.

Configuration via a mapping file (e.g., `spex/plugin-integrations.yml`) that maps plugin names to skills/enforcement to add:

```yaml
# Example structure
plugins:
  prose:
    detect: "~/.claude/plugins/cc-prose"
    skills:
      - prose:check
      - prose:rewrite
    inject_into:
      - review-spec: "Run prose:check on spec content before accepting"
      - review-code: "Run prose:check on documentation changes"
  copyedit:
    detect: "~/.claude/plugins/cc-copyedit"
    skills:
      - copyedit:consistency
      - copyedit:flow
    inject_into:
      - review-spec: "Run copyedit:consistency on spec terminology"
```

This keeps the ecosystem composable without hardcoding plugin knowledge into extensions.

### Version bump and clean slate

- All extension manifests require `>=0.7.4`
- Remove all legacy migration code
- No backwards compatibility with pre-0.7 spec-kit

## What stays from 016

- The five extension bundles and their command markdown files
- spex-gates hooks for ad-hoc quality gates
- spex-teams standalone command pattern
- spex-worktrees after_specify hook
- spex-deep-review commands

## What changes from 016

- Ship command replaced by workflow YAML
- Init script dramatically simplified
- Plugin detection system added (configurable)
- All manifests bumped to `>=0.7.4`
- Legacy migration code removed entirely
- Hook/workflow coordination mechanism added

## Open Questions (resolved)

1. ~~Plugin detection scope~~ -> Configurable via mapping file
2. ~~Ship oversight levels~~ -> Maps to gate auto-approve behavior
3. ~~Legacy migration cutoff~~ -> Remove everything, clean slate

## Scope

This is a follow-on spec (017) that builds on top of the extension work already done in 016. It refactors ship, init, and adds plugin detection, but does not redo the extension bundle creation.
