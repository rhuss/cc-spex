# Brainstorm: Teams Trait Consolidation

**Date:** 2026-03-08
**Status:** idea
**Related:** brainstorm/01-teams-integration.md, specs/005-teams-traits/

## Problem

The current SDD plugin has two teams traits that create confusion:

1. **teams-vanilla**: Basic parallel task orchestration via Agent Teams
2. **teams-spec** (aka teams-review): Spec guardian pattern where lead reviews, teammates implement in worktrees

When both traits are active on a project, the implement skill contains conflicting instructions. In practice, this leads to the model ignoring BOTH traits and falling back to regular `Agent` tool calls with `run_in_background`, which defeats the purpose entirely.

### Observed Failure Mode (cc-deck project, 2026-03-08)

With both `teams-vanilla` and `teams-spec` active:
- The implement skill contained both trait blocks
- `teams-spec` said "This overrides teams-vanilla when both are active"
- The model read both, got confused about which to follow, and used neither
- Instead used `Agent` tool with `run_in_background` (regular background agents, not Agent Teams)
- Result: no worktree isolation, merge conflicts on shared files (main.rs, sidebar.rs), compile errors from different API assumptions

### Root Causes

1. **Advisory instructions get ignored under cognitive load**: The teams traits are embedded as trait blocks in the implement skill. Under the pressure of implementation planning + beads management + file reading, the model takes the path of least resistance.

2. **No enforcement**: Unlike the skill gate hook (which blocks tool calls), there's no mechanism to enforce Agent Teams usage.

3. **Trait conflict not resolved upfront**: Both traits inject instructions, and the "teams-spec overrides teams-vanilla" note is buried in the teams-spec block. The model has to read both, understand the priority, then act. Under load, it skips this.

4. **Pre-flight is advisory**: "Check if CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is enabled" is a note, not a gate.

5. **teams-vanilla is a dependency, not an alternative**: teams-spec builds on top of teams-vanilla (same spawning mechanism), but they're presented as separate opt-in traits.

## Proposed Solution: Consolidate to a Single "teams" Trait

### Core Idea

Merge `teams-vanilla` and `teams-spec` into a single `teams` trait that always uses the spec guardian pattern. The vanilla orchestration becomes the internal implementation detail (how teammates are spawned), not a separate mode.

### Why Spec Guardian Should Be the Default

- **It's strictly better**: Vanilla orchestration is just "spawn teammates and merge". Spec guardian adds review before merge. There's no scenario where you want parallel implementation WITHOUT spec compliance checking.
- **Eliminates the conflict**: One trait, one behavior, no ambiguity.
- **Enforces quality**: The lead reviews each teammate's work against spec.md before accepting, catching the kind of API mismatches we saw (Key vs KeyWithModifier).

### Trait Activation

```yaml
# In project's .specify/config.yaml or via /sdd:traits
traits:
  - teams    # Single trait, replaces teams-vanilla + teams-spec
```

### Decision Gate (Implementation Skill)

The consolidated trait should inject a **decision gate at the TOP** of the implement skill, not buried in a trait block:

```markdown
## Agent Teams: MANDATORY for Multi-Task Implementation

**ENFORCEMENT**: This section is NON-NEGOTIABLE when implementing 2+ independent tasks.

### Decision Gate (BEFORE any implementation)

When the implement skill is invoked with multiple tasks:

1. **CHECK**: Is `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` set?
   - If not: Set it in `.claude/settings.local.json`, inform user restart needed, STOP.
   - If yes: proceed.

2. **DELEGATE**: Call `{Skill: sdd:teams-orchestrate}` for task graph analysis,
   teammate spawning in worktrees, spec compliance review, and merge coordination.
   Do NOT proceed with direct implementation.

### Anti-patterns (NEVER do these)
- Using `Agent` tool with `run_in_background` instead of Agent Teams
- Implementing tasks directly when 2+ independent tasks exist
- Skipping the pre-flight check

### When teams are NOT needed
- Single sequential task with no parallelism opportunity
- Pure verification/validation work (clippy, test runs)
- Fixing a single compile error or merge conflict
```

### Skill Consolidation

| Current | Proposed |
|---------|----------|
| `sdd:teams-orchestrate` (vanilla) | `sdd:teams-orchestrate` (spec guardian, includes spawning) |
| `sdd:teams-spec-guardian` (review) | Merged into `sdd:teams-orchestrate` |
| `sdd:teams-research` (parallel research) | Keep as-is (different use case) |

The `sdd:teams-orchestrate` skill would:
1. Analyze task graph for parallelism (from teams-vanilla)
2. Spawn teammates in git worktrees (from teams-spec)
3. Review each teammate's work against spec.md (from teams-spec)
4. Only merge compliant changes (from teams-spec)
5. Use beads bridge for persistence (from teams-spec)

### Hook-Based Enforcement (Optional)

Consider a PreToolUse hook that detects when the model uses `Agent` with `run_in_background` during an active implement skill session and warns:

```
WARNING: You should be using Agent Teams (sdd:teams-orchestrate) for parallel
implementation, not regular background agents. Use {Skill: sdd:teams-orchestrate}.
```

This is softer than blocking (hooks can't distinguish all contexts), but adds a nudge.

## Migration Path

1. Create new `teams` trait that contains the consolidated spec guardian behavior
2. Make `teams-vanilla` and `teams-spec` aliases that both resolve to `teams`
3. Update skill templates to use the decision gate pattern
4. Deprecation notice for old trait names
5. Remove aliases after one release cycle

## Open Questions

- Should the decision gate be a hook (hard enforcement) or prompt injection (soft guidance)?
- Should `teams-research` also be folded in, or stay separate?
- What's the minimum task count threshold for mandatory teams usage? (Proposed: 2+ independent tasks)
- How to handle the case where Agent Teams env var isn't set and user can't restart? (Fallback to sequential?)
