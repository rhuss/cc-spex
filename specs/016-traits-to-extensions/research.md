# Research: Replace Traits with Spec-Kit Extensions

**Date**: 2026-04-09 | **Branch**: `016-traits-to-extensions`

## R1: Extension System Mechanics

**Decision**: Use spec-kit's native extension system (schema_version 1.0) as the replacement for traits/overlays.

**Rationale**: The git extension already demonstrates a working pattern: manifest (`extension.yml`), commands (markdown files), hooks (lifecycle before/after events), config (YAML with template/active split), and registry (JSON tracking). This is a proven, upstream-supported mechanism.

**Alternatives considered**: Custom extension format (rejected: duplicates upstream work), keeping overlays alongside extensions (rejected: two parallel systems).

### Key Mechanics

- **Install**: `specify extension add <path> --dev` copies extension to `.specify/extensions/<id>/`, registers commands for detected agent, merges hooks into `.specify/extensions.yml`
- **Registry**: `.specify/extensions/.registry` (JSON) tracks version, source, manifest_hash, enabled state, priority, registered_commands per agent
- **Hooks**: Aggregated in `.specify/extensions.yml` with `extension`, `command`, `enabled`, `optional`, `prompt`, `description`, `condition` fields
- **Hook events**: before/after variants of: constitution, specify, clarify, plan, tasks, implement, checklist, analyze, taskstoissues
- **Agent detection**: spec-kit detects agent from integration manifests (`.specify/integrations/claude.manifest.json`), maps commands to agent-specific directories
- **Enable/disable**: `specify extension enable/disable <id>` toggles the `enabled` field in registry and hooks

### Manifest Schema (from git extension reference)

```yaml
schema_version: "1.0"
extension:
  id: <string>
  name: <string>
  version: <semver>
  description: <string>
  author: <string>
  repository: <url>
  license: <string>
requires:
  speckit_version: <semver-range>
  tools: [{name: <string>, required: <bool>}]
provides:
  commands: [{name: <dotted-name>, file: <path>, description: <string>}]
  config: [{name: <filename>, template: <filename>, description: <string>, required: <bool>}]
hooks:
  <event_name>:
    command: <dotted-name>
    optional: <bool>
    prompt: <string>
    description: <string>
tags: [<string>]
config:
  defaults: {<key>: <value>}
```

## R2: Migration Mapping

**Decision**: Create 5 extensions from existing overlays, skills, and commands. Drop deprecated content.

### Extension: `spex` (core, always active)

| Source Type | Current Location | New Command Name |
|-------------|-----------------|------------------|
| Skill | `spex/skills/brainstorm/` | `speckit.spex.brainstorm` |
| Skill | `spex/skills/ship/` | `speckit.spex.ship` |
| Skill | `spex/skills/help/` | `speckit.spex.help` |
| Skill | `spex/skills/init/` | `speckit.spex.init` |
| Skill | `spex/skills/evolve/` | `speckit.spex.evolve` |
| Skill | `spex/skills/spec-refactoring/` | `speckit.spex.spec-refactoring` |
| Skill | `spex/skills/spec-kit/` | (internal, merged into init) |
| Skill | `spex/skills/using-superpowers/` | (internal, merged into routing) |
| Overlay | `_ship-guard/*` (5 files) | Inline in ship command (always active) |
| Command | `spex/commands/traits.md` | `speckit.spex.extensions` (renamed) |

### Extension: `spex-gates` (replaces `superpowers` trait)

| Source Type | Current Location | New Command Name |
|-------------|-----------------|------------------|
| Skill | `spex/skills/review-spec/` | `speckit.spex-gates.review-spec` |
| Skill | `spex/skills/review-plan/` | `speckit.spex-gates.review-plan` |
| Skill | `spex/skills/review-code/` | `speckit.spex-gates.review-code` |
| Skill | `spex/skills/verification-before-completion/` | `speckit.spex-gates.verify` |
| Command | `spex/commands/stamp.md` | `speckit.spex-gates.stamp` |
| Overlay | `superpowers/speckit-specify` | Hook: `after_specify` |
| Overlay | `superpowers/speckit-plan` | Hook: `after_plan` |
| Overlay | `superpowers/speckit-implement` | Hook: `after_implement` |

### Extension: `spex-worktrees` (replaces `worktrees` trait)

| Source Type | Current Location | New Command Name |
|-------------|-----------------|------------------|
| Skill | `spex/skills/worktree/` | `speckit.spex-worktrees.worktree` |
| Overlay | `worktrees/speckit-specify` | Hook: `after_specify` (optional) |
| Overlay | `worktrees/speckit-plan` | (context note, inline in command) |
| Overlay | `worktrees/speckit-implement` | (context note, inline in command) |

### Extension: `spex-teams` (replaces `teams` trait)

| Source Type | Current Location | New Command Name |
|-------------|-----------------|------------------|
| Skill | `spex/skills/teams-orchestrate/` | `speckit.spex-teams.orchestrate` |
| Skill | `spex/skills/teams-research/` | `speckit.spex-teams.research` |
| (New) | N/A | `speckit.spex-teams.implement` (standalone) |
| Overlay | `teams/speckit-plan` | Hook: `before_plan` (research routing) |

### Extension: `spex-deep-review` (replaces `deep-review` trait)

| Source Type | Current Location | New Command Name |
|-------------|-----------------|------------------|
| Skill | `spex/skills/deep-review/` | `speckit.spex-deep-review.review` |
| Overlay | `deep-review/speckit-implement` | Hook: `after_implement` |

### Drop (deprecated)

- `spex/overlays/teams-vanilla/` (consolidated into teams)
- `spex/overlays/teams-spec/` (consolidated into teams)
- `spex/skills/teams-spec-guardian/` (merged into teams-orchestrate)

## R3: Script Refactoring

**Decision**: Refactor `spex-init.sh`, remove `spex-traits.sh`, minor updates to hooks.

### `spex-init.sh` - REFACTOR

| Component | Action | Details |
|-----------|--------|---------|
| CLI check + version gate | Keep | `specify` CLI >= 0.5.0 detection |
| `specify init --here --ai claude --force` | Keep | Core spec-kit initialization |
| `apply_traits()` | Replace | Install bundled extensions via `specify extension add <path> --dev` |
| Migration functions | Keep (temporarily) | `sdd-traits.json` migration, old command cleanup |
| Gitignore setup | Keep | Pattern configuration |
| Status line config | Keep | Ship pipeline UX |
| Traits warning | Add | Detect old `spex-traits.json`, print deprecation notice |

### `spex-traits.sh` - REMOVE

| Component | Action | Details |
|-----------|--------|---------|
| Overlay apply logic | Remove | Replaced by `specify extension add` |
| Config management | Remove | Replaced by `.specify/extensions/.registry` |
| Enable/disable | Remove | Replaced by `specify extension enable/disable` |
| Permissions management | Relocate | Move to `spex-init.sh` or new `spex-permissions.sh` |
| Agent teams env var | Relocate | Set in init when installing spex-teams extension |
| Dependency checking | Remove | Extension manifest `requires` handles this |

### `context-hook.py` - MINOR UPDATE

| Change | Details |
|--------|---------|
| Config path | Check `.specify/extensions/.registry` instead of `.specify/spex-traits.json` for configured state |
| Context element | Rename `<spex-traits-command>` to reference extension management |
| Init script path | Keep (still needed) |

### `pretool-gate.py` - MINOR UPDATE

| Change | Details |
|--------|---------|
| Teams gate | Read from `.specify/extensions/.registry` (check `extensions.spex-teams.enabled`) instead of `spex-traits.json` |
| All other gates | No changes needed |

### `ship` skill - MINOR UPDATE

| Change | Details |
|--------|---------|
| Prerequisite check | Read from `.specify/extensions/.registry` for `spex-gates` and `spex-deep-review` enabled state |
| External tools config | Move to `spex-deep-review` extension config |
| Teams routing | Check `spex-teams` in registry, route to `speckit.spex-teams.implement` when enabled |

## R4: `_ship-guard` Overlay Handling

**Decision**: `_ship-guard` content becomes part of the core `spex` extension's ship command.

**Rationale**: Ship-guard overlays are always applied (no enable/disable toggle). They inject autonomous pipeline behavior into spec-kit commands. In the extension model, this behavior is best handled by:
1. The ship command itself setting `.spex-state` before invoking each step
2. Each extension command checking `.spex-state` and suppressing prompts when in autonomous mode

This is cleaner than the overlay approach because:
- No content injection into third-party skill files
- Each command owns its autonomous-mode behavior
- The ship command explicitly controls the pipeline flow

## R5: Cross-Extension Dependencies

| Extension | Requires |
|-----------|----------|
| `spex` | None (always installed) |
| `spex-gates` | None |
| `spex-worktrees` | None |
| `spex-teams` | `spex-gates` (quality gates must exist for post-teams review) |
| `spex-deep-review` | `spex-gates` (deep-review runs after spec compliance passes) |

Note: The `requires` field in extension manifests handles these dependencies. `specify extension enable` will validate dependencies automatically.

## R6: Constitution Update Plan

Sections II (Overlay Delegation) and III (Trait Composability) must be rewritten:

- **Section II**: Replace "Overlay Delegation" with "Extension Architecture". Extensions provide commands and hooks. Commands are self-contained markdown files. Hooks wire into spec-kit lifecycle events.
- **Section III**: Replace "Trait Composability" with "Extension Composability". Extensions are independent and combinable via spec-kit's enable/disable mechanism. No sentinel markers or content injection.
- **Plugin Architecture**: Update file organization references from `spex/commands/`, `spex/skills/`, `spex/overlays/` to `spex/extensions/`.
- **Remove**: All references to `spex-traits.sh`, overlay application, sentinel markers, `spex-traits.json`.
