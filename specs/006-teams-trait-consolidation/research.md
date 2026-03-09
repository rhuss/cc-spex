# Research: Teams Trait Consolidation

**Date**: 2026-03-09
**Feature**: 006-teams-trait-consolidation

## Decision 1: Trait Alias Mechanism

**Decision**: Add alias resolution to `sdd-traits.sh` with a mapping table and normalization function.

**Rationale**: The current `sdd-traits.sh` has no alias support. `VALID_TRAITS` is hardcoded on line 31, and `is_valid_trait()` does exact string matching. Adding a resolution layer before validation is the minimal change needed.

**Alternatives considered**:
- Config migration only (rewrite JSON on load): Would break if user manually edits config back to old names
- Symlink overlay directories: Would not handle config normalization or deprecation notices

**Implementation approach**:
- Add `TRAIT_ALIASES` mapping: `teams-vanilla→teams`, `teams-spec→teams`
- Add `resolve_trait_name()` function called before `is_valid_trait()`
- Update `VALID_TRAITS` to include `teams` alongside old names (during transition)
- `ensure_config()` normalizes old names to canonical `teams` when loading
- Deprecation notice printed when old names are used

## Decision 2: Sentinel Marker Strategy

**Decision**: Use a single new sentinel `<!-- SDD-TRAIT:teams -->` for the consolidated overlay. Handle cleanup of old sentinels during `sdd-traits.sh apply`.

**Rationale**: The idempotency check uses `grep` for exact sentinel strings. Old sentinels (`<!-- SDD-TRAIT:teams-vanilla -->`, `<!-- SDD-TRAIT:teams-spec -->`) in already-applied command files must be cleaned up, or the consolidated overlay would append alongside stale blocks.

**Implementation approach**:
- `do_apply()` gains a cleanup phase: before appending new overlays, strip blocks from disabled/aliased traits
- Block removal: delete from sentinel marker to next sentinel marker (or EOF)
- New overlay uses `<!-- SDD-TRAIT:teams -->` sentinel

## Decision 3: Skill Consolidation Strategy

**Decision**: Merge `sdd:teams-spec-guardian` into `sdd:teams-orchestrate`. The orchestrate skill becomes the single entry point with spec guardian as the always-on behavior.

**Rationale**: The two skills share task graph analysis and teammate spawning logic. The spec guardian adds worktree isolation and spec review on top. Since spec guardian is always-on (per clarification), there's no need for a vanilla-only code path.

**Key merged behaviors**:
- Task graph analysis for parallelism (from teams-orchestrate)
- Worktree isolation for each teammate (from teams-spec-guardian)
- Spec compliance review by lead before merge (from teams-spec-guardian)
- Beads bridge for persistence (from teams-spec-guardian)
- Sequential fallback for single tasks (from teams-orchestrate)

**Alternatives considered**:
- Keep both skills, have orchestrate call guardian: Unnecessary indirection
- Create new skill name: Would break existing references in overlays and docs

## Decision 4: Hook-Based Enforcement

**Decision**: Add a new PreToolUse hook (or extend `skill-gate-hook.py`) that detects `Agent` tool calls with `run_in_background` parameter when the `teams` trait is active.

**Rationale**: The existing `skill-gate-hook.py` already demonstrates the PreToolUse hook pattern. A separate hook avoids coupling the skill gate logic with anti-pattern detection.

**Implementation approach**:
- New hook script: `sdd/scripts/hooks/teams-enforce-hook.py`
- Trigger: PreToolUse event for `Agent` tool
- Condition: Check if `run_in_background` is in the tool input AND teams trait is enabled
- Action: Return `"decision": "block"` with message directing to Agent Teams
- Registration: Add to `sdd/hooks.json` when teams trait is enabled
- Context: Hook checks for teams trait via `.specify/sdd-traits.json` or a marker file

## Decision 5: Dependency Graph Update

**Decision**: The consolidated `teams` trait depends on `superpowers` and `beads` (same as teams-spec did).

**Rationale**: The spec guardian pattern uses beads for persistence and superpowers for code review. Since spec guardian is always-on, these dependencies are always needed.

**Updated dependency map**:
- `teams` requires `superpowers beads`
- Old: `teams-spec` required `teams-vanilla superpowers beads`
- `teams-vanilla` dependency is eliminated (vanilla is now internal to teams)

## Decision 6: Plan Overlay Handling

**Decision**: The plan overlay (parallel research via `sdd:teams-research`) moves from `teams-vanilla` to `teams`. Content stays the same.

**Rationale**: `teams-research` is not being consolidated (per spec FR-007). The plan overlay just needs to live under the new `teams` directory instead of `teams-vanilla`.

## Codebase File Inventory

### Files to Modify

| File | Change |
|------|--------|
| `sdd/scripts/sdd-traits.sh` | Add alias support, update VALID_TRAITS, update dependency map, add cleanup in apply |
| `sdd/skills/teams-orchestrate/SKILL.md` | Merge in spec guardian behavior (worktrees, review, beads bridge) |
| `.specify/sdd-traits.json` | Will be normalized on next `sdd-traits.sh apply` |

### Files to Create

| File | Purpose |
|------|---------|
| `sdd/overlays/teams/commands/speckit.implement.append.md` | Consolidated implement overlay with decision gate |
| `sdd/overlays/teams/commands/speckit.plan.append.md` | Plan overlay (moved from teams-vanilla) |
| `sdd/scripts/hooks/teams-enforce-hook.py` | PreToolUse hook for anti-pattern detection |

### Files to Deprecate (keep but mark)

| File | Reason |
|------|--------|
| `sdd/overlays/teams-vanilla/commands/speckit.implement.append.md` | Replaced by teams overlay |
| `sdd/overlays/teams-vanilla/commands/speckit.plan.append.md` | Replaced by teams overlay |
| `sdd/overlays/teams-spec/commands/speckit.implement.append.md` | Replaced by teams overlay |
| `sdd/skills/teams-spec-guardian/SKILL.md` | Merged into teams-orchestrate |

### Files Unchanged

| File | Reason |
|------|--------|
| `sdd/skills/teams-research/SKILL.md` | Different use case, stays separate (FR-007) |
| `sdd/overlays/beads/*` | Orthogonal to teams consolidation |
| `sdd/overlays/superpowers/*` | Orthogonal to teams consolidation |
| `sdd/scripts/hooks/skill-gate-hook.py` | Existing hook, not modified |
| `sdd/scripts/hooks/context-hook.py` | Existing hook, not modified |
