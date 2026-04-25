# 09: Replace Traits with Spec-Kit Extensions

## Problem

The spex traits system (overlay-based skill injection) is:
- Claude Code specific (doesn't work with other coding agents)
- A parallel system to spec-kit's own extension mechanism
- Maintenance burden (sentinel markers, idempotent apply, overlay resolution)

Spec-kit already has a comprehensive extension system with commands, hooks, config management, and multi-agent support. We should use it.

## Decision

Replace the entire traits system with spec-kit extensions. No overlays, no `spex-traits.sh`, no sentinel markers.

## Architecture

### cc-spex Plugin (Minimal Bootstrap)

```
cc-spex plugin
├── scripts/
│   ├── spex-init.sh              # bootstrap: specify init + install extensions
│   └── hooks/
│       ├── context-hook.py       # session context injection
│       └── pretool-gate.py       # skill enforcement
├── hooks.json                    # hook definitions
└── extensions/                   # bundled extensions (installed during init)
    ├── spex/                     # core orchestration (always installed)
    ├── spex-gates/               # review quality gates
    ├── spex-worktrees/           # git worktree isolation
    ├── spex-teams/               # parallel implementation
    └── spex-deep-review/         # multi-agent code review
```

**Eliminated entirely:** `overlays/`, `spex-traits.sh`, plugin `skills/`, plugin `commands/`

### Extensions

| Extension | Commands | Hooks |
|-----------|----------|-------|
| **spex** (always) | `speckit.spex.brainstorm`, `.ship`, `.evolve`, `.help` | none (orchestrators) |
| **spex-gates** | `speckit.spex-gates.review-spec`, `.review-code`, `.review-plan`, `.verify` | `after_specify`, `after_plan`, `after_implement` |
| **spex-worktrees** | `speckit.spex-worktrees.create`, `.list`, `.cleanup` | `after_specify` (optional) |
| **spex-teams** | `speckit.spex-teams.research`, `.orchestrate` | `before_plan` (optional), `before_implement` (pre-empts) |
| **spex-deep-review** | `speckit.spex-deep-review.run` | `after_implement` |

### Command Namespace

All commands under `speckit.spex*`:

```
speckit.spex.brainstorm
speckit.spex.ship
speckit.spex.evolve
speckit.spex.help

speckit.spex-gates.review-spec
speckit.spex-gates.review-code
speckit.spex-gates.review-plan
speckit.spex-gates.verify

speckit.spex-worktrees.create
speckit.spex-worktrees.list
speckit.spex-worktrees.cleanup

speckit.spex-teams.research
speckit.spex-teams.orchestrate

speckit.spex-deep-review.run
```

### Init Flow

```bash
specify init --here --ai claude --force
specify extension add "$PLUGIN_ROOT/extensions/spex" --dev
specify extension add "$PLUGIN_ROOT/extensions/spex-gates" --dev
specify extension add "$PLUGIN_ROOT/extensions/spex-worktrees" --dev
specify extension add "$PLUGIN_ROOT/extensions/spex-teams" --dev
specify extension add "$PLUGIN_ROOT/extensions/spex-deep-review" --dev
```

### Enable/Disable (replaces spex-traits.sh)

```bash
specify extension enable spex-gates       # was: spex-traits.sh enable superpowers
specify extension disable spex-teams      # was: spex-traits.sh disable teams
```

Disabled extensions: commands unregistered, skills removed, hooks deactivated. Zero context pollution.

### Ship Pipeline (simplified)

```
speckit.spex.ship:
  1. Set .spex-state (autonomous flag)
  2. /speckit.specify     -> after_specify hook: review-spec (if spex-gates enabled)
  3. /speckit.plan        -> after_plan hook: review-plan (if spex-gates enabled)
  4. /speckit.tasks
  5. /speckit.implement   -> before_implement: teams pre-empt (if spex-teams enabled)
                          -> after_implement: deep-review (if spex-deep-review enabled)
                          -> after_implement: review-code + verify (if spex-gates enabled)
  6. Create PR
  7. Clear .spex-state
```

Ship skips clarify. Autonomous mode assumes spec is ready.

### Teams Pre-emption

The `before_implement` hook from spex-teams analyzes tasks.md. If 2+ independent tasks exist, it pre-empts the implement command with parallel team orchestration. This replaces the old overlay behavioral injection.

## Key Design Decisions

1. **No overlays** - all functionality via extension commands + lifecycle hooks
2. **No inter-extension dependencies** - each extension stands alone
3. **Clean break migration** - re-init required for existing users
4. **Ship skips clarify** - autonomous mode assumes spec is ready
5. **Multiple extensions with spex- prefix** - enables granular enable/disable without context pollution
6. **Extensions bundled in plugin** - installed from local path during init
7. **No forced task breakdown** - users/ship sequences steps explicitly

## Trait-to-Extension Mapping

| Old Trait | New Extension | Notes |
|-----------|--------------|-------|
| superpowers | spex-gates | Review quality gates only |
| worktrees | spex-worktrees | Direct mapping |
| teams | spex-teams | Behavioral injection replaced by before_implement pre-emption |
| deep-review | spex-deep-review | Direct mapping |
| _ship-guard | eliminated | Ship pipeline handles its own state |

## What's Gained

- **Agent portability**: Extensions work with Claude, Codex, Kimi, any agent
- **Upstream alignment**: Using spec-kit's own plugin system
- **Simpler plugin**: cc-spex becomes pure bootstrap + hooks
- **No overlay machinery**: No sentinel markers, no append/prepend, no stale cleanup
- **Clean enable/disable**: Extension system handles registration/deregistration
- **Discovery**: Extensions are catalog-publishable for sharing

## What's Changed for Users

- `/spex:review-spec` becomes `/speckit.spex-gates.review-spec`
- `/spex:traits enable X` becomes `specify extension enable spex-X`
- Re-init required (clean break)
- Ship no longer runs clarify in autonomous mode

## Open Items

- Hook ordering: multiple `after_implement` hooks (deep-review before verify) need guaranteed sequential execution in manifest order
- `spex:traits` command: keep as thin wrapper around `specify extension enable/disable`, or drop entirely?
- Init defaults: install all extensions by default? Let user choose?
- Ship-mode awareness: do hook commands need to detect autonomous mode, or does the hook system handle this?
