# Review Summary: Teams Trait Consolidation

**Spec:** specs/006-teams-trait-consolidation/spec.md | **Plan:** specs/006-teams-trait-consolidation/plan.md
**Generated:** 2026-03-09

---

## Executive Summary

The SDD plugin currently offers two separate traits for parallel task implementation: `teams-vanilla` (basic parallel spawning) and `teams-spec` (spec guardian pattern with worktree isolation and compliance review). When both are enabled on a project, the model receives conflicting instructions. Under the cognitive load of implementation planning, beads management, and file operations, the model takes the path of least resistance and ignores both trait blocks entirely. It falls back to regular `Agent` tool calls with `run_in_background`, which provides no worktree isolation, no spec compliance checking, and leads to merge conflicts and API mismatches between parallel workers.

This feature consolidates the two traits into a single `teams` trait that always uses the spec guardian pattern. The vanilla orchestration (task graph analysis, teammate spawning) becomes an internal implementation detail rather than a separate mode. The spec guardian behavior (worktree isolation, per-task spec review before merge, beads persistence) is always-on by design, since it is strictly better than unreviewed parallel implementation.

The implementation adds three key mechanisms: (1) trait alias resolution in `sdd-traits.sh` so existing projects with `teams-vanilla` or `teams-spec` in their config migrate automatically, (2) a consolidated overlay with a decision gate placed at the top of the implement skill (not buried in trait blocks), and (3) a PreToolUse hook that blocks the model from using `Agent` with `run_in_background` as an escape hatch. Together, these changes eliminate the observed failure mode where advisory instructions get ignored, replacing soft guidance with hard enforcement at the hook level while keeping prompt-level guidance for the model's benefit.

The `sdd:teams-research` skill (parallel codebase research during planning) is unaffected and remains separate, as it serves a different workflow phase with different requirements.

## PR Contents

This spec PR includes the following artifacts:

| Artifact | Description |
|----------|-------------|
| `spec.md` | Defines consolidation requirements: single trait, decision gate, alias support, anti-pattern detection |
| `plan.md` | Implementation approach: alias resolution in sdd-traits.sh, consolidated overlays, merged skill, PreToolUse hook |
| `tasks.md` | 28 tasks across 7 phases, organized by user story priority |
| `research.md` | 6 design decisions: alias mechanism, sentinel strategy, skill consolidation, hook enforcement, dependencies, plan overlay |
| `checklists/requirements.md` | Specification quality checklist (all items pass) |
| `review-summary.md` | This file |

## Technical Decisions

### Decision 1: Hook + Prompt Enforcement (vs. Prompt-Only)
- **Chosen approach:** PreToolUse hook blocks `Agent` with `run_in_background` when teams trait is active, combined with prompt-level guidance text
- **Alternatives considered:**
  - Prompt injection only: Rejected because the original problem is exactly that advisory instructions get ignored under cognitive load
  - Hook only (no prompt text): Rejected because prompt guidance helps the model understand why it should use Agent Teams, reducing blocked attempts
- **Trade-off:** Slightly more infrastructure (hook script + registration) in exchange for reliable enforcement
- **Reviewer question:** Is there risk of the hook being too aggressive, blocking legitimate `Agent` + `run_in_background` calls outside of implement sessions?

### Decision 2: Spec Guardian Always-On (vs. Configurable)
- **Chosen approach:** Spec guardian review is always-on, no opt-out for vanilla-only mode
- **Alternatives considered:**
  - Configurable `review: false` option: Rejected because it reintroduces the choice complexity that caused the original problem
  - Separate skill for advanced users: Rejected because maintaining two code paths defeats consolidation
- **Trade-off:** Loss of flexibility for users who want fast, unreviewed parallel work. Gain: eliminated ambiguity and guaranteed quality.

### Decision 3: Overlay Cleanup in apply (vs. Manual Removal)
- **Chosen approach:** `do_apply()` gains a cleanup phase that strips blocks from disabled/aliased traits before appending new ones
- **Alternatives considered:**
  - Require manual cleanup of old sentinel blocks: Rejected because users would have stale conflicting blocks
  - Full file regeneration: Rejected because it would destroy non-trait content in command files
- **Trade-off:** More complex apply logic, but automatic migration for existing projects

## Critical References

| Reference | Why it needs attention |
|-----------|----------------------|
| `spec.md` FR-009: Hook enforcement | Core enforcement mechanism. Must correctly distinguish anti-pattern (Agent + run_in_background) from legitimate usage |
| `plan.md` Design Details §3: Overlay Cleanup | Sentinel block removal logic is delicate. Must not corrupt non-trait content in command files |
| `plan.md` Design Details §5: Consolidated Orchestrate Skill | Largest single change. Merges two skills into one while preserving all spec guardian behaviors |
| `spec.md` Edge Cases: Merge conflicts between teammates | Not fully addressed in tasks. Relies on existing teams-spec-guardian conflict handling |

## Reviewer Checklist

### Verify
- [ ] Alias resolution handles all edge cases: `teams`, `teams-vanilla`, `teams-spec`, and combinations
- [ ] Overlay cleanup correctly identifies block boundaries (sentinel to next sentinel or EOF)
- [ ] Consolidated orchestrate skill preserves all spec guardian behaviors (worktrees, review, beads bridge)
- [ ] Hook does not block legitimate Agent tool usage (e.g., Explore subagents, research agents)

### Question
- [ ] Should the old overlay directories (`teams-vanilla/`, `teams-spec/`) be deleted after one release cycle, or kept indefinitely as documentation?
- [ ] Is the hook the right enforcement point, or should the decision gate also be enforced in the `sdd:beads-execute` skill that drives task execution?

### Watch out for
- [ ] Sentinel block removal in `do_apply()` could corrupt files if block boundaries are miscalculated
- [ ] The consolidated skill is significantly larger than either original skill. May approach cognitive load limits for the model reading it
- [ ] Config normalization in `ensure_config()` modifies user's JSON file on read. Could be surprising if user inspects the file

## Scope Boundaries
- **In scope:** Trait consolidation, alias support, overlay/skill merging, hook enforcement, deprecation markers
- **Out of scope:** `sdd:teams-research` changes, beads bridge changes, Agent Teams runtime behavior, alias removal (future release)
- **Why these boundaries:** Focus on fixing the observed failure mode (conflicting traits ignored) without disrupting orthogonal systems

## Naming and Schema Decisions

| Item | Name | Context |
|------|------|---------|
| Consolidated trait | `teams` | Replaces `teams-vanilla` and `teams-spec` |
| Consolidated skill | `sdd:teams-orchestrate` | Keeps existing name, absorbs guardian behavior |
| Hook script | `teams-enforce-hook.py` | PreToolUse hook in `sdd/scripts/hooks/` |
| Sentinel marker | `<!-- SDD-TRAIT:teams -->` | New canonical sentinel for consolidated overlay |

## Risk Areas

| Risk | Impact | Mitigation |
|------|--------|------------|
| Overlay cleanup corrupts command files | High | Block boundary detection uses sentinel markers as delimiters. Test with multiple trait combinations before release |
| Hook blocks legitimate Agent usage | Medium | Hook only triggers on `run_in_background` parameter. Subagent spawning (TeamCreate, Explore) uses different parameters |
| Consolidated skill too large for model | Medium | Keep skill focused on delegation structure, not inline logic. Use `{Skill: sdd:review-code}` for review details |
| Config normalization surprises users | Low | Print notice when normalizing: "Migrated teams-vanilla/teams-spec to teams in config" |

---
*Share this with reviewers. Full context in linked spec and plan.*
